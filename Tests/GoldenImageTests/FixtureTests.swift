import CoreGraphics
import CoreImage
@testable import GoldenImage
import Metal
import Testing

@Test("Size variations - test all fixture sizes")
func testSizeVariations() throws {
    let sizes = ["tiny_1x1", "small_8x8", "medium_256x256", "large_2048x2048", "huge_4096x4096"]

    for size in sizes {
        let image1 = try loadFixture(size)
        let image2 = try loadFixture(size)
        let result = try imagesAreIdentical(image1, image2)
        #expect(result == true, "Same fixture loaded twice should be identical: \(size)")
    }
}

@Test("Threadgroup edge cases - tiny images")
func testThreadgroupSizes() throws {
    let tiny = try loadFixture("tiny_1x1")
    let small = try loadFixture("small_8x8")

    #expect(try imagesAreIdentical(tiny, tiny))
    #expect(try imagesAreIdentical(small, small))
}

@Test("Benchmark large images - 8192x8192 comparison", .timeLimit(.minutes(1)))
func testBenchmarkLargeImages() throws {
    let ultra = try loadFixture("ultra_8192x8192")
    let device = TextureComparer.shared.device
    let texture = try makeTexture(from: ultra, device: device)

    let gpuStart = Date()
    let psnr = try calculatePSNR(lhs: texture, rhs: texture)
    let gpuElapsed = Date().timeIntervalSince(gpuStart)

    let cpuStart = Date()
    let cpuResult = cpuCompare(texture, texture)
    let cpuElapsed = Date().timeIntervalSince(cpuStart)

    print("8192x8192 GPU PSNR: \(String(format: "%.3f", gpuElapsed * 1000))ms")
    print("8192x8192 CPU byte compare: \(String(format: "%.3f", cpuElapsed * 1000))ms")
    print("GPU speedup: \(String(format: "%.2f", cpuElapsed / gpuElapsed))x")

    #expect(psnr.isInfinite, "Ultra large image should match itself")
    #expect(cpuResult == true, "CPU should also report as identical")
}

@Test("Subtle difference - single pixel changed by 1/255")
func testSinglePixelSmallChange() throws {
    let base = try loadFixture("subtle_base")
    let changed = try loadFixture("subtle_1px_off")

    let result = try imagesAreDifferent(base, changed)
    #expect(result == true, "Single pixel change by 1 should be detected")
}

@Test("Subtle difference - single pixel changed by 128/255")
func testSinglePixelLargeChange() throws {
    let base = try loadFixture("subtle_base")
    let changed = try loadFixture("subtle_1px_large")

    let result = try imagesAreDifferent(base, changed)
    #expect(result == true, "Single pixel change by 128 should be detected")
}

@Test("Subtle difference - 10 pixels changed slightly")
func testMultiplePixelSubtle() throws {
    let base = try loadFixture("subtle_base")
    let changed = try loadFixture("subtle_10px_off")

    let result = try imagesAreDifferent(base, changed)
    #expect(result == true, "10 pixels changed by 1 should be detected")
}

@Test("Broad difference - 50% of image different")
func testHalfImageDifferent() throws {
    let base = try loadFixture("broad_base")
    let half = try loadFixture("broad_half")

    let result = try imagesAreDifferent(base, half)
    #expect(result == true, "50% different pixels should be detected")
}

@Test("Broad difference - completely different image")
func testCompletelyDifferent() throws {
    let base = try loadFixture("broad_base")
    let all = try loadFixture("broad_all")

    let result = try imagesAreDifferent(base, all)
    #expect(result == true, "Completely different images should be detected")
}

@Test("Alpha channel - fully opaque")
func testAlphaOpaque() throws {
    let opaque = try loadFixture("alpha_opaque")
    #expect(try imagesAreIdentical(opaque, opaque))
}

@Test("Alpha channel - fully transparent")
func testAlphaTransparent() throws {
    let transparent = try loadFixture("alpha_transparent")
    #expect(try imagesAreIdentical(transparent, transparent))
}

@Test("Alpha channel - partial transparency (50%)")
func testAlphaPartial() throws {
    let alpha50 = try loadFixture("alpha_50")
    #expect(try imagesAreIdentical(alpha50, alpha50))
}

@Test("Alpha channel - gradient transparency")
func testAlphaGradient() throws {
    let gradient = try loadFixture("alpha_gradient")
    #expect(try imagesAreIdentical(gradient, gradient))
}

@Test("Alpha channel - pattern transparency")
func testAlphaPattern() throws {
    let pattern = try loadFixture("alpha_pattern")
    #expect(try imagesAreIdentical(pattern, pattern))
}

@Test("Alpha channel - opaque vs transparent are different")
func testAlphaOpaqueVsTransparent() throws {
    let opaque = try loadFixture("alpha_opaque")
    let transparent = try loadFixture("alpha_transparent")
    #expect(try imagesAreDifferent(opaque, transparent))
}

@Test("Color space - sRGB red self-comparison")
func testColorSpaceSRGB() throws {
    let srgb = try loadFixture("srgb_red")
    #expect(try imagesAreIdentical(srgb, srgb))
}

@Test("Color space - all color spaces normalize to sRGB")
func testColorSpaceNormalization() throws {
    let srgb = try loadFixture("srgb_red")
    let p3 = try loadFixture("p3_red")
    let generic = try loadFixture("generic_red")

    #expect(try imagesAreIdentical(srgb, srgb))
    #expect(try imagesAreIdentical(p3, p3))
    #expect(try imagesAreIdentical(generic, generic))
}

@Test("Edge case - all black image")
func testAllBlack() throws {
    let black = try loadFixture("all_black")
    #expect(try imagesAreIdentical(black, black))
}

@Test("Edge case - all white image")
func testAllWhite() throws {
    let white = try loadFixture("all_white")
    #expect(try imagesAreIdentical(white, white))
}

@Test("Edge case - all transparent image")
func testAllTransparent() throws {
    let transparent = try loadFixture("all_transparent")
    #expect(try imagesAreIdentical(transparent, transparent))
}

@Test("Edge case - black vs white are different")
func testBlackVsWhite() throws {
    let black = try loadFixture("all_black")
    let white = try loadFixture("all_white")
    #expect(try imagesAreDifferent(black, white))
}

@Test("Identical baseline - same image loaded twice")
func testIdenticalFiles() throws {
    let a = try loadFixture("baseline_a")
    let b = try loadFixture("baseline_b")
    let result = try imagesAreIdentical(a, b)
    #expect(result == true, "Identical fixture files should match")
}
