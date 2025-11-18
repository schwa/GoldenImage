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

    return try TextureCompare.shared.calculatePSNR(lhs, rhs)
}

/// Calculate PSNR between two CGImages. Automatically saves comparison if environment variables are set.
/// - Parameters:
///   - lhs: First image to compare
///   - rhs: Second image to compare
///   - lhsPath: Path/identifier for first image (used in saved metadata)
///   - rhsPath: Path/identifier for second image (used in saved metadata)
/// - Returns: PSNR value in dB (infinity for identical images)
public func calculatePSNR(lhs: CGImage, rhs: CGImage, lhsPath: String, rhsPath: String) throws -> Double {
    guard lhs.width == rhs.width, lhs.height == rhs.height else {
        throw TextureComparisonError.dimensionMismatch
    }

    guard let device = MTLCreateSystemDefaultDevice() else {
        throw TextureComparisonError.metalNotSupported
    }

    let texture1 = try makeTexture(from: lhs, device: device)
    let texture2 = try makeTexture(from: rhs, device: device)

    let psnr = try TextureCompare.shared.calculatePSNR(texture1, texture2)

    // Automatically save if environment variables are set
    if let config = ImageSaverConfiguration.fromEnvironment() {
        let saver = ImageSaver(configuration: config)
        _ = try saver.saveComparison(
            image1: lhs,
            image2: rhs,
            imagePath1: lhsPath,
            imagePath2: rhsPath,
            psnr: psnr
        )
    }

    return psnr
}
