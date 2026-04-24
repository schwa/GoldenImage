import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct GoldenImageComparison {
    public struct Options: OptionSet, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let none = Self([])

        // If set then we save our input image to disk first then compare via url
        public static let roundTripToDisk = Self(rawValue: 1 << 0)

        // If set do not do compare alpha
        public static let ignoreAlpha = Self(rawValue: 2 << 0)

        // If set copy any images we use to temp
        public static let copyToTemp = Self(rawValue: 3 << 0)

        /// If set, the match also passes when the edge-aware (eroded) PSNR meets
        /// `psnrThreshold`, even if standard PSNR does not. Useful when the
        /// rasterizer being tested is known to produce ±1px anti-aliasing
        /// differences along shape edges. See `ImageComparison.Result.erodedPSNR`
        /// for caveats around 1px-wide features.
        public static let ignoreEdgeAAHalos = Self(rawValue: 1 << 2)
    }

    public var imageDirectory: URL
    public var options: Options
    /// PSNR threshold for considering images as matching.
    /// Default is 120 dB (identical or nearly identical).
    /// Use lower values (e.g., 40 dB) for tests with text/fonts that may vary slightly.
    public var psnrThreshold: Double
    /// Directory where images are written when no golden image exists for a test.
    /// When `nil`, defaults to `<temporaryDirectory>/GoldenImages`.
    public var failureOutputDirectory: URL?

    public init(
        imageDirectory: URL,
        options: Options = .none,
        psnrThreshold: Double = 120.0,
        failureOutputDirectory: URL? = nil
    ) {
        self.imageDirectory = imageDirectory
        self.options = options
        self.psnrThreshold = psnrThreshold
        self.failureOutputDirectory = failureOutputDirectory
    }

    public func image(image: CGImage, matchesGoldenImageNamed name: String) throws -> Bool {
        // Find golden image in the directory
        let goldenImageURL = FileManager.default.url(ofDirectory: imageDirectory, named: name, conformingTo: .image)

        guard let extendedLinearSRGB = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) else {
            throw GoldenImageError.failedToCreateColorSpace
        }

        // If no golden image exists, always save the input image for manual copying
        guard let goldenImageURL else {
            let outputDir = failureOutputDirectory
                ?? FileManager.default.temporaryDirectory.appendingPathComponent("GoldenImages")
            let tempURL = outputDir.appendingPathComponent("\(name).png")

            // Create directory if needed
            try FileManager.default.createDirectory(at: tempURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            // Normalize to extended linear sRGB before saving
            guard let normalizedImage = image.copy(colorSpace: extendedLinearSRGB) else {
                throw GoldenImageError.failedToNormalizeImage
            }
            try normalizedImage.write(to: tempURL)

            throw GoldenImageError.noGoldenImage(savedTo: tempURL)
        }

        // Load golden image from disk
        guard let imageSource = CGImageSourceCreateWithURL(goldenImageURL as CFURL, nil),
            let goldenImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw GoldenImageError.noGoldenImage(savedTo: nil)
        }

        // Normalize both images to extended linear sRGB for consistent comparison
        guard let normalizedInput = image.copy(colorSpace: extendedLinearSRGB),
            let normalizedGolden = goldenImage.copy(colorSpace: extendedLinearSRGB) else {
            throw GoldenImageError.failedToNormalizeImage
        }

        // Validate dimensions match
        guard normalizedInput.width == normalizedGolden.width,
            normalizedInput.height == normalizedGolden.height else {
            throw TextureComparisonError.dimensionMismatch
        }

        // Handle roundTripToDisk option - save normalized input and reload it
        let comparisonImage: CGImage
        if options.contains(.roundTripToDisk) {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("GoldenImageRoundTrip-\(UUID()).png")

            try normalizedInput.write(to: tempURL)
            defer { try? FileManager.default.removeItem(at: tempURL) }

            guard let imageSource = CGImageSourceCreateWithURL(tempURL as CFURL, nil),
                let reloadedImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw GoldenImageError.noGoldenImage(savedTo: nil)
            }

            // Normalize reloaded image to extended linear sRGB (PNG may lose extended range flag)
            guard let normalizedReloaded = reloadedImage.copy(colorSpace: extendedLinearSRGB) else {
                throw GoldenImageError.failedToNormalizeImage
            }
            comparisonImage = normalizedReloaded
        } else {
            comparisonImage = normalizedInput
        }

        // TODO: Handle copyToTemp option
        // TODO: Handle ignoreAlpha option

        let result = try ImageComparison().compare(comparisonImage, normalizedGolden)

        // Return true if PSNR meets threshold, or (optionally) if the edge-aware
        // eroded PSNR meets the threshold.
        if result.psnr >= psnrThreshold {
            return true
        }
        if options.contains(.ignoreEdgeAAHalos), (result.erodedPSNR ?? 0) >= psnrThreshold {
            return true
        }
        return false
    }
}

public enum GoldenImageError: Error {
    case noGoldenImage(savedTo: URL?)
    case failedToCreateColorSpace
    case failedToNormalizeImage
}
