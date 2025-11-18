import CoreGraphics
import CoreImage
@testable import GoldenImage
import Metal
import Testing

@Test("Sanity - basic solid color comparison with runtime generation")
func testBasicSolidColorComparison() throws {
    let red1 = try createSolidColorTexture(width: 256, height: 256, color: (1.0, 0.0, 0.0, 1.0))
    let red2 = try createSolidColorTexture(width: 256, height: 256, color: (1.0, 0.0, 0.0, 1.0))
    let blue = try createSolidColorTexture(width: 256, height: 256, color: (0.0, 0.0, 1.0, 1.0))

    #expect(try imagesAreIdentical(red1, red2), "Identical red textures should match")
    #expect(try imagesAreDifferent(red1, blue), "Red and blue should be different")
}

@Test("Sanity - dimension mismatch throws error")
func testDimensionMismatchError() throws {
    let small = try createSolidColorTexture(width: 64, height: 64, color: (0.5, 0.5, 0.5, 1.0))
    let large = try createSolidColorTexture(width: 256, height: 256, color: (0.5, 0.5, 0.5, 1.0))

    #expect(throws: TextureComparisonError.dimensionMismatch) {
        _ = try calculatePSNR(lhs: small, rhs: large)
    }
}
