import CoreImage
import Foundation
import Metal
import CoreGraphics
import SwiftUI

public struct ImageComparison: Sendable {
    struct Options: OptionSet {
        let rawValue: Int

        static let none = Options([])
    }


    public init() {

    }

    public struct Result: Hashable, Sendable {
        public var psnr: Double

        public var isMatch: Bool {
            psnr >= 120.0
        }
    }
}

public extension ImageComparison {
    func compare(_ lhs: CGImage, _ rhs: CGImage) throws -> Result {
        let cpuCompare = CPUCompare()
        let psnr = try cpuCompare.compare(lhs, rhs)
        return Result(psnr: psnr)
    }

    /// Create a grayscale difference image between two images.
    /// Each pixel's intensity represents the normalized difference where 0 (black) means identical
    /// and 1 (white) means maximum difference.
    /// - Parameters:
    ///   - lhs: First image to compare
    ///   - rhs: Second image to compare
    /// - Returns: A grayscale CGImage showing per-pixel differences
    func differenceImage(_ lhs: CGImage, _ rhs: CGImage) throws -> CGImage {
        let cpuCompare = CPUCompare()
        return try cpuCompare.differenceImage(lhs, rhs)
    }
}

public extension ImageComparison {
    @MainActor
    func compare(_ lhs: Image, _ rhs: Image) throws -> Result {
        let renderer1 = ImageRenderer(content: lhs)
        let renderer2 = ImageRenderer(content: rhs)

        guard let lhsImage = renderer1.cgImage else {
            throw TextureComparisonError.failedToCreateTexture
        }

        guard let rhsImage = renderer2.cgImage else {
            throw TextureComparisonError.failedToCreateTexture
        }

        return try compare(lhsImage, rhsImage)
    }
}

public extension ImageComparison {
    func compare(_ lhs: URL, _ rhs: URL) throws -> Result {
        guard let lhsImageSource = CGImageSourceCreateWithURL(lhs as CFURL, nil),
              let lhsImage = CGImageSourceCreateImageAtIndex(lhsImageSource, 0, nil) else {
            throw TextureComparisonError.failedToCreateTexture
        }

        guard let rhsImageSource = CGImageSourceCreateWithURL(rhs as CFURL, nil),
              let rhsImage = CGImageSourceCreateImageAtIndex(rhsImageSource, 0, nil) else {
            throw TextureComparisonError.failedToCreateTexture
        }

        return try compare(lhsImage, rhsImage)
    }

    /// Create a grayscale difference image between two images at the given URLs.
    func differenceImage(_ lhs: URL, _ rhs: URL) throws -> CGImage {
        guard let lhsImageSource = CGImageSourceCreateWithURL(lhs as CFURL, nil),
              let lhsImage = CGImageSourceCreateImageAtIndex(lhsImageSource, 0, nil) else {
            throw TextureComparisonError.failedToCreateTexture
        }

        guard let rhsImageSource = CGImageSourceCreateWithURL(rhs as CFURL, nil),
              let rhsImage = CGImageSourceCreateImageAtIndex(rhsImageSource, 0, nil) else {
            throw TextureComparisonError.failedToCreateTexture
        }

        return try differenceImage(lhsImage, rhsImage)
    }
}

public extension ImageComparison {
    func compare(_ lhs: CIImage, _ rhs: CIImage) throws -> Result {
        let context = CIContext()

        guard let lhsImage = context.createCGImage(lhs, from: lhs.extent) else {
            throw TextureComparisonError.failedToCreateTexture
        }

        guard let rhsImage = context.createCGImage(rhs, from: rhs.extent) else {
            throw TextureComparisonError.failedToCreateTexture
        }

        return try compare(lhsImage, rhsImage)
    }

    /// Create a grayscale difference image between two CIImages.
    func differenceImage(_ lhs: CIImage, _ rhs: CIImage) throws -> CGImage {
        let context = CIContext()

        guard let lhsImage = context.createCGImage(lhs, from: lhs.extent) else {
            throw TextureComparisonError.failedToCreateTexture
        }

        guard let rhsImage = context.createCGImage(rhs, from: rhs.extent) else {
            throw TextureComparisonError.failedToCreateTexture
        }

        return try differenceImage(lhsImage, rhsImage)
    }
}

public extension ImageComparison {
    func compare(_ lhs: MTLTexture, _ rhs: MTLTexture) throws -> Result {
        guard lhs.width == rhs.width, lhs.height == rhs.height else {
            throw TextureComparisonError.dimensionMismatch
        }

        let psnr = try TextureCompare.shared.calculatePSNR(lhs, rhs)
        return Result(psnr: psnr)
    }
}

