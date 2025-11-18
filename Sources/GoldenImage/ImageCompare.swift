import CoreGraphics
import CoreImage
import Foundation
import Metal
import MetalKit

/// Calculate PSNR between two textures using GPU acceleration. Returns infinity for identical images.
public func calculatePSNR(lhs: MTLTexture, rhs: MTLTexture) throws -> Double {
    guard lhs.width == rhs.width, lhs.height == rhs.height else {
        throw TextureComparisonError.dimensionMismatch
    }

    return try TextureComparer.shared.calculatePSNR(lhs, rhs)
}
