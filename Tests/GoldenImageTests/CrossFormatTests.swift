import CoreGraphics
import CoreImage
@testable import GoldenImage
import ImageIO
import Metal
import Testing

@Test("Cross-format - gradient via CIImage")
func testGradientViaCIImage() throws {
    let fixture = "gradient_smooth"
    let ciImage1 = try loadFixture(fixture)
    let ciImage2 = try loadFixture(fixture)

    #expect(try imagesAreIdentical(ciImage1, ciImage2), "Same CIImage loaded twice should match")
}

@Test("Cross-format - gradient via CGImage")
func testGradientViaCGImage() throws {
    let fixture = "gradient_smooth"
    let cgImage1 = try loadCGImageFixture(fixture)
    let cgImage2 = try loadCGImageFixture(fixture)

    let device = TextureCompare.shared.device
    let texture1 = try makeTexture(from: cgImage1, device: device)
    let texture2 = try makeTexture(from: cgImage2, device: device)

    #expect(try imagesAreIdentical(texture1, texture2), "Same CGImage loaded twice should match")
}

@Test("Cross-format - pattern via CIImage")
func testPatternViaCIImage() throws {
    let fixture = "pattern_sharp"
    let ciImage1 = try loadFixture(fixture)
    let ciImage2 = try loadFixture(fixture)

    #expect(try imagesAreIdentical(ciImage1, ciImage2), "Same CIImage loaded twice should match")
}

@Test("Cross-format - pattern via CGImage")
func testPatternViaCGImage() throws {
    let fixture = "pattern_sharp"
    let cgImage1 = try loadCGImageFixture(fixture)
    let cgImage2 = try loadCGImageFixture(fixture)

    let device = TextureCompare.shared.device
    let texture1 = try makeTexture(from: cgImage1, device: device)
    let texture2 = try makeTexture(from: cgImage2, device: device)

    #expect(try imagesAreIdentical(texture1, texture2), "Same CGImage loaded twice should match")
}

@Test("Cross-format - alpha via CIImage")
func testAlphaViaCIImage() throws {
    let fixture = "alpha_gradient"
    let ciImage1 = try loadFixture(fixture)
    let ciImage2 = try loadFixture(fixture)

    #expect(try imagesAreIdentical(ciImage1, ciImage2), "Same CIImage loaded twice should match")
}

@Test("Cross-format - alpha via CGImage")
func testAlphaViaCGImage() throws {
    let fixture = "alpha_gradient"
    let cgImage1 = try loadCGImageFixture(fixture)
    let cgImage2 = try loadCGImageFixture(fixture)

    let device = TextureCompare.shared.device
    let texture1 = try makeTexture(from: cgImage1, device: device)
    let texture2 = try makeTexture(from: cgImage2, device: device)

    #expect(try imagesAreIdentical(texture1, texture2), "Same CGImage loaded twice should match")
}

@Test("Cross-format - large (4096x4096) via CIImage")
func testLargeViaCIImage() throws {
    let fixture = "huge_4096x4096"
    let ciImage1 = try loadFixture(fixture)
    let ciImage2 = try loadFixture(fixture)

    #expect(try imagesAreIdentical(ciImage1, ciImage2), "Same large CIImage loaded twice should match")
}

@Test("Cross-format - large (4096x4096) via CGImage")
func testLargeViaCGImage() throws {
    let fixture = "huge_4096x4096"
    let cgImage1 = try loadCGImageFixture(fixture)
    let cgImage2 = try loadCGImageFixture(fixture)

    let device = TextureCompare.shared.device
    let texture1 = try makeTexture(from: cgImage1, device: device)
    let texture2 = try makeTexture(from: cgImage2, device: device)

    #expect(try imagesAreIdentical(texture1, texture2), "Same large CGImage loaded twice should match")
}

func loadCGImageFixture(_ name: String) throws -> CGImage {
    guard let fixtureURL = Bundle.module.url(forResource: "Fixtures/\(name.replacingOccurrences(of: ".png", with: ""))", withExtension: "png") else {
        throw TestError.fixtureNotFound(name)
    }

    guard let imageSource = CGImageSourceCreateWithURL(fixtureURL as CFURL, nil) else {
        throw TestError.fixtureNotFound(name)
    }

    guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
        throw TestError.fixtureNotFound(name)
    }

    return cgImage
}
