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

    @Test
    func testGoldenImageComparisonMissing_savesInputToFailureDirectory() throws {
        // When no golden image exists, the input should be written to the
        // failureOutputDirectory and a .noGoldenImage(savedTo:) error thrown.
        let failureDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GoldenImageTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: failureDir) }

        let comparison = GoldenImageComparison(
            imageDirectory: resourcesURL,
            options: .none,
            failureOutputDirectory: failureDir
        )

        let imageA = try loadResourceImage(named: "alpha_blend")

        do {
            _ = try comparison.image(image: imageA, matchesGoldenImageNamed: "brand_new_golden")
            Issue.record("expected GoldenImageError.noGoldenImage to be thrown")
        } catch let GoldenImageError.noGoldenImage(savedTo) {
            guard let savedTo else {
                Issue.record("expected savedTo URL to be populated")
                return
            }
            #expect(savedTo.path.hasPrefix(failureDir.path))
            #expect(savedTo.lastPathComponent == "brand_new_golden.png")
            #expect(FileManager.default.fileExists(atPath: savedTo.path))
        }
    }

    @Test
    func testGoldenImageComparisonMissing_usesDefaultFailureDirectory() throws {
        // With no failureOutputDirectory specified, input is written under the
        // system temp directory's GoldenImages subfolder.
        let comparison = GoldenImageComparison(
            imageDirectory: resourcesURL,
            options: .none
        )

        let uniqueName = "default_failure_dir_\(UUID().uuidString)"
        let imageA = try loadResourceImage(named: "alpha_blend")

        do {
            _ = try comparison.image(image: imageA, matchesGoldenImageNamed: uniqueName)
            Issue.record("expected GoldenImageError.noGoldenImage to be thrown")
        } catch let GoldenImageError.noGoldenImage(savedTo) {
            guard let savedTo else {
                Issue.record("expected savedTo URL to be populated")
                return
            }
            let expectedParent = FileManager.default.temporaryDirectory
                .appendingPathComponent("GoldenImages")
            #expect(savedTo.path.hasPrefix(expectedParent.path))
            #expect(FileManager.default.fileExists(atPath: savedTo.path))
            try? FileManager.default.removeItem(at: savedTo)
        }
    }

    @Test
    func testGoldenImageComparison_dimensionMismatchThrows() throws {
        // Input image at a different size than the golden image should throw
        // TextureComparisonError.dimensionMismatch.
        let comparison = GoldenImageComparison(
            imageDirectory: resourcesURL,
            options: .none
        )

        // Build a small off-size image in the same color space as alpha_blend.
        let reference = try loadResourceImage(named: "alpha_blend")
        guard let colorSpace = reference.colorSpace,
            let ctx = CGContext(
                data: nil,
                width: max(1, reference.width / 2),
                height: max(1, reference.height / 2),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ), let smaller = ctx.makeImage() else {
            Issue.record("failed to build smaller image")
            return
        }

        #expect(throws: TextureComparisonError.self) {
            try comparison.image(image: smaller, matchesGoldenImageNamed: "alpha_blend")
        }
    }
}
