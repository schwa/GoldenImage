import CoreGraphics
import CoreImage
import Foundation
import Metal
import SwiftUI

public struct ImageComparison: Sendable {
    public init() {
        // No-op.
    }

    public struct Result: Hashable, Sendable {
        public var psnr: Double

        /// Edge-aware PSNR that ignores thin (single-pixel) differences such as
        /// anti-aliasing halos along shape edges.
        ///
        /// Computed by applying a 3×3 morphological erosion (minimum filter) to the
        /// per-pixel squared-error map before averaging: any error pixel that has a
        /// zero-error neighbor is zeroed out. Solid regions of error survive.
        ///
        /// `nil` when the underlying comparison path does not support it
        /// (currently the `MTLTexture` overload).
        ///
        /// **Caveat:** the 3×3 erosion kernel cannot distinguish a genuine
        /// single-pixel-wide feature (e.g. a 1pt stroke, a hairline, an isolated
        /// pixel-art detail) from an anti-aliasing halo — both will be erased.
        /// Empirically, strokes ≥3pt are preserved within ~3 dB of `psnr`, 2pt
        /// strokes inflate by ~5 dB, and 1pt strokes can vanish entirely (jumping
        /// to 120 dB). Treat `psnr` as the primary signal and `erodedPSNR` as a
        /// secondary check answering "does the difference survive edge erosion?".
        /// A large gap between the two means the differences are concentrated at
        /// edges; a small gap means the differences are solid/interior.
        public var erodedPSNR: Double?

        public init(psnr: Double, erodedPSNR: Double? = nil) {
            self.psnr = psnr
            self.erodedPSNR = erodedPSNR
        }

        public var isMatch: Bool {
            psnr >= 120.0
        }

        /// Edge-aware variant of `isMatch`: true when the eroded PSNR meets the
        /// match threshold, even if standard PSNR does not.
        ///
        /// Useful for tests where the actual and expected images are functionally
        /// identical but differ along anti-aliased edges (e.g. comparing two
        /// rasterizers of the same vector artwork). See `erodedPSNR` for the
        /// caveats around 1px-wide features.
        ///
        /// Returns `false` when `erodedPSNR` is `nil`.
        public var isMatchIgnoringEdges: Bool {
            (erodedPSNR ?? 0) >= 120.0
        }
    }
}

public extension ImageComparison {
    func compare(_ lhs: CGImage, _ rhs: CGImage) throws -> Result {
        let cpuCompare = CPUCompare()
        let detailed = try cpuCompare.compareDetailed(lhs, rhs)
        return Result(psnr: detailed.psnr, erodedPSNR: detailed.erodedPSNR)
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

private func loadImage(at url: URL) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw TextureComparisonError.failedToCreateTexture
    }
    return image
}

public extension ImageComparison {
    func compare(_ lhs: URL, _ rhs: URL) throws -> Result {
        try compare(loadImage(at: lhs), loadImage(at: rhs))
    }

    /// Create a grayscale difference image between two images at the given URLs.
    func differenceImage(_ lhs: URL, _ rhs: URL) throws -> CGImage {
        try differenceImage(loadImage(at: lhs), loadImage(at: rhs))
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
