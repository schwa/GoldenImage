import CoreImage
@testable import GoldenImage
import Metal
import Testing

@Test("GPU vs CPU: Identical images")
func verifyIdenticalImages() throws {
    let texture1 = try createSolidColorTexture(width: 512, height: 512, color: (1.0, 0.5, 0.25, 1.0))
    let texture2 = try createSolidColorTexture(width: 512, height: 512, color: (1.0, 0.5, 0.25, 1.0))

    let gpuResult = try imagesAreIdentical(texture1, texture2)
    let cpuResult = cpuCompare(texture1, texture2)

    #expect(gpuResult == true, "GPU should report images as equal")
    #expect(cpuResult == true, "CPU should report images as equal")
    #expect(gpuResult == cpuResult, "GPU and CPU results must match")
}

@Test("GPU vs CPU: Different images")
func verifyDifferentImages() throws {
    let texture1 = try createSolidColorTexture(width: 512, height: 512, color: (1.0, 0.0, 0.0, 1.0))
    let texture2 = try createSolidColorTexture(width: 512, height: 512, color: (0.0, 1.0, 0.0, 1.0))

    let gpuResult = try imagesAreIdentical(texture1, texture2)
    let cpuResult = cpuCompare(texture1, texture2)

    #expect(gpuResult == false, "GPU should report images as different")
    #expect(cpuResult == false, "CPU should report images as different")
    #expect(gpuResult == cpuResult, "GPU and CPU results must match")
}

@Test("GPU vs CPU: Single pixel difference")
func verifySinglePixelDifference() throws {
    let texture1 = try createSolidColorTexture(width: 256, height: 256, color: (0.5, 0.5, 0.5, 1.0))
    let texture2 = try createSolidColorTexture(width: 256, height: 256, color: (0.5, 0.5, 0.5, 1.0))

    let pixel: [UInt8] = [255, 0, 0, 255]
    texture2.replace(region: MTLRegionMake2D(128, 128, 1, 1), mipmapLevel: 0, withBytes: pixel, bytesPerRow: 4)

    let gpuResult = try imagesAreIdentical(texture1, texture2)
    let cpuResult = cpuCompare(texture1, texture2)

    #expect(gpuResult == false, "GPU should detect single pixel difference")
    #expect(cpuResult == false, "CPU should detect single pixel difference")
    #expect(gpuResult == cpuResult, "GPU and CPU results must match")
}

@Test("GPU vs CPU: Large gradient images")
func verifyGradientImages() throws {
    let texture1 = try createGradientTexture(width: 1_024, height: 1_024)
    let texture2 = try createGradientTexture(width: 1_024, height: 1_024)

    let gpuResult = try imagesAreIdentical(texture1, texture2)
    let cpuResult = cpuCompare(texture1, texture2)

    #expect(gpuResult == true, "GPU should report gradients as equal")
    #expect(cpuResult == true, "CPU should report gradients as equal")
    #expect(gpuResult == cpuResult, "GPU and CPU results must match")
}

@Test("GPU vs CPU: All fixture images")
func verifyAllFixtures() throws {
    let fixtures = [
        "baseline_a", "gradient_smooth", "pattern_sharp",
        "alpha_opaque", "all_black", "all_white", "medium_256x256"
    ]

    for fixture in fixtures {
        let ciImage = try loadFixture(fixture)
        let comparer = TextureCompare.shared
        let texture1 = try makeTexture(from: ciImage, device: comparer.device)
        let texture2 = try makeTexture(from: ciImage, device: comparer.device)

        let gpuResult = try imagesAreIdentical(texture1, texture2)
        let cpuResult = cpuCompare(texture1, texture2)

        #expect(gpuResult == true, "\(fixture): GPU should report as equal")
        #expect(cpuResult == true, "\(fixture): CPU should report as equal")
        #expect(gpuResult == cpuResult, "\(fixture): GPU and CPU results must match")
    }
}

@Test("Verify known differences are detected")
func verifyKnownDifferences() throws {
    struct TestCase {
        let color1: (CGFloat, CGFloat, CGFloat, CGFloat)
        let color2: (CGFloat, CGFloat, CGFloat, CGFloat)
        let shouldMatch: Bool
        let description: String
    }

    let testCases = [
        TestCase(color1: (1.0, 0.0, 0.0, 1.0), color2: (1.0, 0.0, 0.0, 1.0), shouldMatch: true, description: "Identical red"),
        TestCase(color1: (1.0, 0.0, 0.0, 1.0), color2: (0.0, 1.0, 0.0, 1.0), shouldMatch: false, description: "Red vs Green"),
        TestCase(color1: (0.5, 0.5, 0.5, 1.0), color2: (0.5, 0.5, 0.5, 0.5), shouldMatch: false, description: "Different alpha"),

        TestCase(color1: (0.0, 0.0, 0.0, 1.0), color2: (0.001, 0.0, 0.0, 1.0), shouldMatch: true, description: "Within quantization"),
        TestCase(color1: (0.0, 0.0, 0.0, 1.0), color2: (0.01, 0.0, 0.0, 1.0), shouldMatch: false, description: "Outside quantization")
    ]

    for testCase in testCases {
        let texture1 = try createSolidColorTexture(width: 128, height: 128, color: testCase.color1)
        let texture2 = try createSolidColorTexture(width: 128, height: 128, color: testCase.color2)

        let gpuResult = try imagesAreIdentical(texture1, texture2)
        let cpuResult = cpuCompare(texture1, texture2)

        #expect(gpuResult == testCase.shouldMatch, "\(testCase.description): GPU expected \(testCase.shouldMatch), got \(gpuResult)")
        #expect(cpuResult == testCase.shouldMatch, "\(testCase.description): CPU expected \(testCase.shouldMatch), got \(cpuResult)")
        #expect(gpuResult == cpuResult, "\(testCase.description): GPU and CPU must agree")
    }
}

@Test("Randomized comparison verification", arguments: [42, 123, 999, 2_024, 12_345])
func randomizedVerification(seed: Int) throws {
    srand48(seed)

    let width = 256
    let height = 256

    var pixels1 = [UInt8](repeating: 0, count: width * height * 4)
    var pixels2 = [UInt8](repeating: 0, count: width * height * 4)

    for i in 0..<pixels1.count {
        pixels1[i] = UInt8(drand48() * 255)
        pixels2[i] = pixels1[i]
    }

    let comparer = TextureCompare.shared
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm,
        width: width,
        height: height,
        mipmapped: false
    )
    descriptor.usage = [.shaderRead]

    guard let texture1 = comparer.device.makeTexture(descriptor: descriptor),
          let texture2 = comparer.device.makeTexture(descriptor: descriptor) else {
        throw TextureComparisonError.failedToCreateTexture
    }

    texture1.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: pixels1, bytesPerRow: width * 4)
    texture2.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: pixels2, bytesPerRow: width * 4)

    let gpuResult1 = try imagesAreIdentical(texture1, texture2)
    let cpuResult1 = cpuCompare(texture1, texture2)

    #expect(gpuResult1 == true, "Random identical: GPU should report equal")
    #expect(cpuResult1 == true, "Random identical: CPU should report equal")
    #expect(gpuResult1 == cpuResult1, "Random identical: Results must match")

    let pixelCount = width * height
    let randomPixelIndex = Int(drand48() * Double(pixelCount))
    let randomChannel = Int(drand48() * 3.0)
    let randomIndex = randomPixelIndex * 4 + randomChannel
    pixels2[randomIndex] = UInt8((Int(pixels2[randomIndex]) + 128) % 256)
    texture2.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: pixels2, bytesPerRow: width * 4)

    let gpuResult2 = try imagesAreDifferent(texture1, texture2)
    let cpuResult2 = cpuCompare(texture1, texture2)

    #expect(gpuResult2 == true, "Random different: GPU should report different")
    #expect(cpuResult2 == false, "Random different: CPU should report different")
    #expect(gpuResult2 != cpuResult2, "Random different: Results must differ (GPU uses PSNR, CPU uses byte comparison)")
}
