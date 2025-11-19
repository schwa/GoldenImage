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

        public static let none = Options([])

        // If set then we save our input image to disk first then compare via url
        public static let roundTripToDisk = Options(rawValue: 1 << 0)

        // If set do not do compare alpha
        public static let ignoreAlpha = Options(rawValue: 2 << 0)

        // If set copy any images we use to temp
        public static let copyToTemp = Options(rawValue: 3 << 0)
    }

    public var imageDirectory: URL
    public var options: Options

    public init(imageDirectory: URL, options: Options) {
        self.imageDirectory = imageDirectory
        self.options = options
    }

    public func image(image: CGImage, matchesGoldenImageNamed name: String) throws -> Bool {
        // Find golden image in the directory
        let goldenImageURL = FileManager.default.url(ofDirectory: imageDirectory, named: name, conformingTo: .image)

        // If no golden image exists, always save the input image to temp for manual copying
        if goldenImageURL == nil {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("GoldenImages")
                .appendingPathComponent("\(name).png")

            // Create directory if needed
            try FileManager.default.createDirectory(at: tempURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            // Normalize to extended linear sRGB before saving
            let targetColorSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
            let normalizedImage = image.copy(colorSpace: targetColorSpace)!
            try normalizedImage.write(to: tempURL)

            throw GoldenImageError.noGoldenImage(savedTo: tempURL)
        }

        // Load golden image from disk
        guard let imageSource = CGImageSourceCreateWithURL(goldenImageURL! as CFURL, nil),
              let goldenImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw GoldenImageError.noGoldenImage(savedTo: nil)
        }

        // Normalize both images to extended linear sRGB for consistent comparison
        let targetColorSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        let normalizedInput = image.copy(colorSpace: targetColorSpace)!
        let normalizedGolden = goldenImage.copy(colorSpace: targetColorSpace)!

        // Validate dimensions match
        guard normalizedInput.width == normalizedGolden.width,
              normalizedInput.height == normalizedGolden.height else {
            throw TextureComparisonError.dimensionMismatch
        }

        // Handle roundTripToDisk option - save normalized input and reload it
        let comparisonImage: CGImage
        if options.contains(.roundTripToDisk) {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(name).png")

            try normalizedInput.write(to: tempURL)

            guard let imageSource = CGImageSourceCreateWithURL(tempURL as CFURL, nil),
                  let reloadedImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw GoldenImageError.noGoldenImage(savedTo: nil)
            }

            // Normalize reloaded image to extended linear sRGB (PNG may lose extended range flag)
            comparisonImage = reloadedImage.copy(colorSpace: targetColorSpace)!
        } else {
            comparisonImage = normalizedInput
        }

        // TODO: Handle copyToTemp option
        // TODO: Handle ignoreAlpha option

        let result = try ImageComparison().compare(comparisonImage, normalizedGolden)

        // Return true if images are identical (PSNR >= 120 dB)
        return result.psnr >= 120.0
    }
}

enum GoldenImageError: Error {
    case noGoldenImage(savedTo: URL?)
}
