import CoreGraphics
import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// Configuration for saving comparison images
public struct ImageSaverConfiguration {
    /// Directory to save images. If nil, uses FileManager's temporary directory
    public let outputDirectory: String?

    /// Whether to reveal the output directory in Finder (macOS only)
    public let revealInFinder: Bool

    /// Whether to enable logging
    public let loggingEnabled: Bool

    public init(outputDirectory: String? = nil, revealInFinder: Bool = false, loggingEnabled: Bool = false) {
        self.outputDirectory = outputDirectory
        self.revealInFinder = revealInFinder
        self.loggingEnabled = loggingEnabled
    }

    /// Create configuration from environment variables
    public static func fromEnvironment() -> ImageSaverConfiguration? {
        let env = ProcessInfo.processInfo.environment

        // Check if saving is enabled
        guard env["GOLDEN_IMAGE_OUTPUT"] != nil || env["GOLDEN_IMAGE_OUTPUT_PATH"] != nil else {
            return nil
        }

        return ImageSaverConfiguration(
            outputDirectory: env["GOLDEN_IMAGE_OUTPUT_PATH"],
            revealInFinder: env["GOLDEN_IMAGE_OUTPUT_REVEAL"] != nil,
            loggingEnabled: env["GOLDEN_IMAGE_LOGGING"] != nil
        )
    }
}

/// Saves comparison images to disk with metadata
public struct ImageSaver {
    private let configuration: ImageSaverConfiguration
    private let logger: Logger?

    public init(configuration: ImageSaverConfiguration) {
        self.configuration = configuration
        self.logger = configuration.loggingEnabled
            ? Logger(subsystem: "com.goldenimage.library", category: "image-saver")
            : nil
    }

    /// Save comparison images to a timestamped subdirectory
    public func saveComparison(
        image1: CGImage,
        image2: CGImage,
        imagePath1: String,
        imagePath2: String,
        psnr: Double
    ) throws -> URL {
        let fileManager = FileManager.default

        // Determine output directory
        let baseOutputURL: URL
        if let outputDir = configuration.outputDirectory {
            baseOutputURL = URL(fileURLWithPath: outputDir)
        } else {
            baseOutputURL = fileManager.temporaryDirectory.appendingPathComponent("golden-image-comparisons")
        }

        // Create output directory if it doesn't exist
        try fileManager.createDirectory(at: baseOutputURL, withIntermediateDirectories: true, attributes: nil)

        // Generate filenames based on the original image names
        let name1 = URL(fileURLWithPath: imagePath1).deletingPathExtension().lastPathComponent
        let name2 = URL(fileURLWithPath: imagePath2).deletingPathExtension().lastPathComponent

        // Create timestamped subdirectory
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())

        let subdirName = "\(name1)_vs_\(name2)_\(timestamp)"
        let subdirURL = baseOutputURL.appendingPathComponent(subdirName)
        try fileManager.createDirectory(at: subdirURL, withIntermediateDirectories: true, attributes: nil)

        // Save images
        let image1URL = subdirURL.appendingPathComponent("\(name1).png")
        let image2URL = subdirURL.appendingPathComponent("\(name2).png")

        try saveImage(image1, to: image1URL)
        try saveImage(image2, to: image2URL)

        // Save metadata
        let metadataURL = subdirURL.appendingPathComponent("comparison.txt")
        let psnrString = psnr.isInfinite ? "∞" : String(format: "%.2f", psnr)
        let metadata = """
        Image Comparison Results
        =======================
        Timestamp: \(timestamp)
        Image 1: \(imagePath1)
        Image 2: \(imagePath2)
        PSNR: \(psnrString) dB
        Dimensions: \(image1.width)×\(image1.height)
        """
        try metadata.write(to: metadataURL, atomically: true, encoding: .utf8)

        logger?.info("Images saved to: \(subdirURL.path)")

        // Reveal in Finder if requested (macOS only)
        #if os(macOS)
        if configuration.revealInFinder {
            NSWorkspace.shared.selectFile(subdirURL.path, inFileViewerRootedAtPath: "")
            logger?.info("Revealed in Finder")
        }
        #endif

        return subdirURL
    }

    private func saveImage(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ImageSaverError.failedToCreateDestination(url.path)
        }

        CGImageDestinationAddImage(destination, image, nil)

        guard CGImageDestinationFinalize(destination) else {
            throw ImageSaverError.failedToWriteImage(url.path)
        }
    }
}

/// Errors that can occur during image saving
public enum ImageSaverError: Error, CustomStringConvertible {
    case failedToCreateDestination(String)
    case failedToWriteImage(String)

    public var description: String {
        switch self {
        case .failedToCreateDestination(let path):
            return "Failed to create image destination at: \(path)"
        case .failedToWriteImage(let path):
            return "Failed to write image to: \(path)"
        }
    }
}
