import CoreGraphics
import Foundation

internal struct CPUCompare: Sendable {

    /// Compare two CGImages using CPU and return PSNR
    /// - Parameters:
    ///   - lhs: First image to compare
    ///   - rhs: Second image to compare
    /// - Returns: PSNR value in dB (120 dB for identical images, capped at 120 dB)
    /// - Throws: TextureComparisonError if images have mismatched dimensions or color spaces
    func compare(_ lhs: CGImage, _ rhs: CGImage) throws -> Double {
        guard lhs.width == rhs.width, lhs.height == rhs.height else {
            throw TextureComparisonError.dimensionMismatch
        }

        guard let lhsColorSpace = lhs.colorSpace,
              let rhsColorSpace = rhs.colorSpace else {
            throw TextureComparisonError.failedToCreateTexture
        }

        guard lhsColorSpace == rhsColorSpace else {
            throw TextureComparisonError.colorSpaceMismatch(lhs: lhsColorSpace, rhs: rhsColorSpace)
        }

        let width = lhs.width
        let height = lhs.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = width * height * bytesPerPixel

        guard let colorSpace = CGColorSpace(name: CGColorSpace.linearSRGB) else {
            throw TextureComparisonError.failedToCreateTexture
        }
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue

        var pixelsA = [UInt8](repeating: 0, count: totalBytes)
        var pixelsB = [UInt8](repeating: 0, count: totalBytes)

        guard let contextA = CGContext(
            data: &pixelsA,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw TextureComparisonError.failedToCreateTexture
        }

        guard let contextB = CGContext(
            data: &pixelsB,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw TextureComparisonError.failedToCreateTexture
        }

        contextA.draw(lhs, in: CGRect(x: 0, y: 0, width: width, height: height))
        contextB.draw(rhs, in: CGRect(x: 0, y: 0, width: width, height: height))

        var sumSquaredDiff: Double = 0.0

        for i in 0..<(width * height) {
            let pixelIndex = i * bytesPerPixel

            let rA = Double(pixelsA[pixelIndex])
            let gA = Double(pixelsA[pixelIndex + 1])
            let bA = Double(pixelsA[pixelIndex + 2])
            let aA = Double(pixelsA[pixelIndex + 3])

            let rB = Double(pixelsB[pixelIndex])
            let gB = Double(pixelsB[pixelIndex + 1])
            let bB = Double(pixelsB[pixelIndex + 2])
            let aB = Double(pixelsB[pixelIndex + 3])

            let diffR = rA - rB
            let diffG = gA - gB
            let diffB = bA - bB
            let diffA = aA - aB

            sumSquaredDiff += diffR * diffR + diffG * diffG + diffB * diffB + diffA * diffA
        }

        let mse = sumSquaredDiff / Double(width * height * 4)

        if mse == 0.0 {
            return 120.0
        }

        let rmse = sqrt(mse)
        let psnr = 20.0 * log10(255.0 / rmse)

        return min(psnr, 120.0)
    }
}
