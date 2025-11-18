import CoreGraphics
import Foundation
import GoldenImage
import ImageIO
import Testing

@Suite("Image Saver Tests")
struct ImageSaverTests {
    @Test("Save comparison images to custom directory")
    func saveToCustomDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("golden-image-test-\(UUID().uuidString)")

        let config = ImageSaverConfiguration(
            outputDirectory: tempDir.path,
            revealInFinder: false,
            loggingEnabled: false
        )

        let saver = ImageSaver(configuration: config)

        // Load test fixtures
        let bundle = Bundle.module
        let baselineAURL = bundle.url(forResource: "baseline_a", withExtension: "png", subdirectory: "Fixtures")!
        let baselineBURL = bundle.url(forResource: "baseline_b", withExtension: "png", subdirectory: "Fixtures")!

        let image1 = try loadCGImage(from: baselineAURL)
        let image2 = try loadCGImage(from: baselineBURL)

        // Save comparison
        let outputURL = try saver.saveComparison(
            image1: image1,
            image2: image2,
            imagePath1: baselineAURL.path,
            imagePath2: baselineBURL.path,
            psnr: .infinity
        )

        // Verify output directory was created
        #expect(FileManager.default.fileExists(atPath: outputURL.path))

        // Verify images were saved
        let image1Output = outputURL.appendingPathComponent("baseline_a.png")
        let image2Output = outputURL.appendingPathComponent("baseline_b.png")
        let metadataOutput = outputURL.appendingPathComponent("comparison.txt")

        #expect(FileManager.default.fileExists(atPath: image1Output.path))
        #expect(FileManager.default.fileExists(atPath: image2Output.path))
        #expect(FileManager.default.fileExists(atPath: metadataOutput.path))

        // Verify metadata content
        let metadata = try String(contentsOf: metadataOutput, encoding: .utf8)
        #expect(metadata.contains("PSNR: ∞ dB"))
        #expect(metadata.contains("512×512"))

        // Clean up
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("Save comparison images to default temp directory")
    func saveToDefaultDirectory() throws {
        let config = ImageSaverConfiguration(
            outputDirectory: nil,
            revealInFinder: false,
            loggingEnabled: false
        )

        let saver = ImageSaver(configuration: config)

        // Load test fixtures
        let bundle = Bundle.module
        let subtleBaseURL = bundle.url(forResource: "subtle_base", withExtension: "png", subdirectory: "Fixtures")!
        let subtle1pxURL = bundle.url(forResource: "subtle_1px_off", withExtension: "png", subdirectory: "Fixtures")!

        let image1 = try loadCGImage(from: subtleBaseURL)
        let image2 = try loadCGImage(from: subtle1pxURL)

        // Save comparison
        let outputURL = try saver.saveComparison(
            image1: image1,
            image2: image2,
            imagePath1: subtleBaseURL.path,
            imagePath2: subtle1pxURL.path,
            psnr: 107.09
        )

        // Verify output directory is in temp
        #expect(outputURL.path.contains("golden-image-comparisons"))

        // Verify metadata has correct PSNR
        let metadataOutput = outputURL.appendingPathComponent("comparison.txt")
        let metadata = try String(contentsOf: metadataOutput, encoding: .utf8)
        #expect(metadata.contains("PSNR: 107.09 dB"))

        // Clean up
        try? FileManager.default.removeItem(at: outputURL)
    }

    @Test("Configuration from environment variables - enabled with GOLDEN_IMAGE_OUTPUT")
    func configurationFromEnvironmentOutput() throws {
        // Set environment variable
        setenv("GOLDEN_IMAGE_OUTPUT", "1", 1)
        defer { unsetenv("GOLDEN_IMAGE_OUTPUT") }

        let config = ImageSaverConfiguration.fromEnvironment()
        #expect(config != nil)
        #expect(config?.outputDirectory == nil)
        #expect(config?.revealInFinder == false)
        #expect(config?.loggingEnabled == false)
    }

    @Test("Configuration from environment variables - with custom output dir")
    func configurationFromEnvironmentOutputDir() throws {
        // Set environment variables
        setenv("GOLDEN_IMAGE_OUTPUT_PATH", "/tmp/test-output", 1)
        setenv("GOLDEN_IMAGE_OUTPUT_REVEAL", "1", 1)
        setenv("GOLDEN_IMAGE_LOGGING", "1", 1)
        defer {
            unsetenv("GOLDEN_IMAGE_OUTPUT_PATH")
            unsetenv("GOLDEN_IMAGE_OUTPUT_REVEAL")
            unsetenv("GOLDEN_IMAGE_LOGGING")
        }

        let config = ImageSaverConfiguration.fromEnvironment()
        #expect(config != nil)
        #expect(config?.outputDirectory == "/tmp/test-output")
        #expect(config?.revealInFinder == true)
        #expect(config?.loggingEnabled == true)
    }

    @Test("Configuration from environment variables - disabled")
    func configurationFromEnvironmentDisabled() throws {
        // Ensure no relevant env vars are set
        unsetenv("GOLDEN_IMAGE_OUTPUT")
        unsetenv("GOLDEN_IMAGE_OUTPUT_PATH")

        let config = ImageSaverConfiguration.fromEnvironment()
        #expect(config == nil)
    }

    @Test("Timestamped subdirectory naming")
    func timestampedSubdirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("golden-image-test-\(UUID().uuidString)")

        let config = ImageSaverConfiguration(outputDirectory: tempDir.path)
        let saver = ImageSaver(configuration: config)

        let bundle = Bundle.module
        let allBlackURL = bundle.url(forResource: "all_black", withExtension: "png", subdirectory: "Fixtures")!
        let allWhiteURL = bundle.url(forResource: "all_white", withExtension: "png", subdirectory: "Fixtures")!

        let image1 = try loadCGImage(from: allBlackURL)
        let image2 = try loadCGImage(from: allWhiteURL)

        let outputURL = try saver.saveComparison(
            image1: image1,
            image2: image2,
            imagePath1: allBlackURL.path,
            imagePath2: allWhiteURL.path,
            psnr: 0.0
        )

        // Verify directory name contains both image names and timestamp
        let dirName = outputURL.lastPathComponent
        #expect(dirName.contains("all_black"))
        #expect(dirName.contains("all_white"))
        #expect(dirName.contains("vs"))

        // Verify timestamp format (yyyy-MM-dd_HH-mm-ss)
        let components = dirName.split(separator: "_")
        #expect(components.count >= 5) // name_vs_name_date_time

        // Clean up
        try? FileManager.default.removeItem(at: tempDir)
    }
}

// Helper function to load CGImage from URL
private func loadCGImage(from url: URL) throws -> CGImage {
    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
        throw NSError(domain: "ImageSaverTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load image from \(url.path)"])
    }
    return cgImage
}
