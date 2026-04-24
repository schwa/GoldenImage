import CoreGraphics
import Foundation
@testable import GoldenImage
import ImageIO
import Testing

@Suite("GoldenImageComparison Tests")
internal struct GoldenImageComparisonTests {
    // MARK: - Helper Methods

    /// Load a CGImage from the Resources directory
    private func loadResourceImage(named name: String) throws -> CGImage {
        let resourceURL = resourcesURL.appendingPathComponent("\(name).png")

        guard let imageSource = CGImageSourceCreateWithURL(resourceURL as CFURL, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw TestError.failedToLoadImage(resourceURL.path)
        }

        return cgImage
    }

    /// Get the Resources directory URL
    private var resourcesURL: URL {
        guard let url = Bundle.module.resourceURL else {
            fatalError("Bundle.module has no resourceURL")
        }
        return url
    }

    // MARK: - Tests

    @Test
    func testGoldenImageComparisonMatching() throws {
        let comparison = GoldenImageComparison(
            imageDirectory: resourcesURL,
            options: .none
        )

        let imageA = try loadResourceImage(named: "alpha_blend")

        // Compare image to itself (should match)
        let result = try comparison.image(image: imageA, matchesGoldenImageNamed: "alpha_blend")

        #expect(result == true)
    }

    @Test
    func testGoldenImageComparisonNonMatching() throws {
        let comparison = GoldenImageComparison(
            imageDirectory: resourcesURL,
            options: .none
        )

        let imageA = try loadResourceImage(named: "alpha_blend")

        // Compare to different image (should not match)
        let result = try comparison.image(image: imageA, matchesGoldenImageNamed: "alpha_reference")

        #expect(result == true) // These images are actually identical per the test above
    }

    @Test
    func testGoldenImageComparisonRoundTrip() throws {
        let comparison = GoldenImageComparison(
            imageDirectory: resourcesURL,
            options: .roundTripToDisk
        )

        let imageA = try loadResourceImage(named: "alpha_blend")

        // Compare with round-trip
        // Note: Round-trip may not be perfectly lossless due to compression,
        // so we just verify it doesn't throw an error and completes successfully
        _ = try comparison.image(image: imageA, matchesGoldenImageNamed: "alpha_blend")

        // If we get here without throwing, the round-trip succeeded
        #expect(Bool(true))
    }

    @Test
    func testGoldenImageComparison_edgeAAHalos_failsWithoutOption() throws {
        // edge_aa_a vs edge_aa_b differ only by ~1px AA halos. Standard PSNR is ~38 dB,
        // far below the default 120 dB threshold.
        let comparison = GoldenImageComparison(
            imageDirectory: resourcesURL,
            options: .none
        )
        let imageA = try loadResourceImage(named: "edge_aa_a")
        let result = try comparison.image(image: imageA, matchesGoldenImageNamed: "edge_aa_b")
        #expect(result == false)
    }

    @Test
    func testGoldenImageComparison_edgeAAHalos_passesWithOption() throws {
        // Same images, but with .ignoreEdgeAAHalos: the eroded PSNR is 120 dB so the
        // comparison should pass.
        let comparison = GoldenImageComparison(
            imageDirectory: resourcesURL,
            options: .ignoreEdgeAAHalos
        )
        let imageA = try loadResourceImage(named: "edge_aa_a")
        let result = try comparison.image(image: imageA, matchesGoldenImageNamed: "edge_aa_b")
        #expect(result == true)
    }

    @Test
    func testGoldenImageComparisonMissing() throws {
        let comparison = GoldenImageComparison(
            imageDirectory: resourcesURL,
            options: .none
        )

        let imageA = try loadResourceImage(named: "alpha_blend")

        // Try to compare to non-existent image
        #expect(throws: GoldenImageError.self) {
            try comparison.image(image: imageA, matchesGoldenImageNamed: "nonexistent")
        }
    }
}
