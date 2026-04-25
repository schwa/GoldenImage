import CoreGraphics
import Foundation

internal struct CPUCompare: Sendable {
    /// Radius (in pixels) of the morphological erosion kernel. Kernel size is
    /// `(2 * erosionRadius + 1)` square. Defaults to 1 (3×3 kernel).
    var erosionRadius: Int = 1

    /// Create a grayscale difference image between two CGImages.
    /// Each pixel's intensity represents the normalized difference (0 = identical, 1 = max difference).
    /// - Parameters:
    ///   - lhs: First image to compare
    ///   - rhs: Second image to compare
    ///   - eroded: If true, apply a `(2r+1)×(2r+1)` morphological erosion to the difference
    ///     map (where `r` is `erosionRadius`) so thin differences (such as AA halos along
    ///     edges) are suppressed.
    ///   - gain: Multiplier applied to the normalized per-pixel difference before clamping
    ///     to `[0, 1]`. Use values >1 to exaggerate very subtle differences (e.g. `gain: 32`
    ///     makes a 1/255 channel diff fully visible). Defaults to 1.0 (no amplification).
    /// - Returns: A grayscale CGImage showing per-pixel differences
    /// - Throws: TextureComparisonError if images have mismatched dimensions or color spaces
    func differenceImage(_ lhs: CGImage, _ rhs: CGImage, eroded: Bool = false, gain: Double = 1.0) throws -> CGImage {
        precondition(gain > 0, "gain must be > 0")
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

        // Maximum possible Euclidean distance in RGBA space: sqrt(4 * 255^2) ≈ 510.0
        let maxDistance = sqrt(4.0 * 255.0 * 255.0)

        // Create grayscale output (1 byte per pixel)
        var grayscalePixels = [UInt8](repeating: 0, count: width * height)

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

            // Euclidean distance normalized to 0-1
            let distance = sqrt(diffR * diffR + diffG * diffG + diffB * diffB + diffA * diffA)
            let normalizedDiff = min(distance / maxDistance * gain, 1.0)

            grayscalePixels[i] = UInt8(normalizedDiff * 255.0)
        }

        if eroded {
            // (2r+1)×(2r+1) morphological erosion: zero out any pixel that has a
            // zero-intensity neighbor within the kernel. Border pixels are treated as
            // having an implicit zero neighbor (conservative).
            let r = erosionRadius
            let source = grayscalePixels
            for y in 0..<height {
                for x in 0..<width {
                    let idx = y * width + x
                    if source[idx] == 0 {
                        continue
                    }
                    if x < r || y < r || x >= width - r || y >= height - r {
                        grayscalePixels[idx] = 0
                        continue
                    }
                    var anyZero = false
                    neighborLoop: for dy in -r...r {
                        for dx in -r...r where dx != 0 || dy != 0 {
                            if source[(y + dy) * width + (x + dx)] == 0 {
                                anyZero = true
                                break neighborLoop
                            }
                        }
                    }
                    if anyZero {
                        grayscalePixels[idx] = 0
                    }
                }
            }
        }

        // Create grayscale CGImage
        guard let grayColorSpace = CGColorSpace(name: CGColorSpace.linearGray) else {
            throw TextureComparisonError.failedToCreateTexture
        }

        let grayBitmapInfo = CGImageAlphaInfo.none.rawValue

        guard let outputContext = CGContext(
            data: &grayscalePixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: grayColorSpace,
            bitmapInfo: grayBitmapInfo
        ) else {
            throw TextureComparisonError.failedToCreateTexture
        }

        guard let outputImage = outputContext.makeImage() else {
            throw TextureComparisonError.failedToCreateTexture
        }

        return outputImage
    }

    /// Detailed PSNR result from a CPU comparison.
    struct DetailedResult {
        /// Standard PSNR, in dB (capped at 120).
        var psnr: Double
        /// Edge-aware PSNR, in dB (capped at 120). See `ImageComparison.Result.erodedPSNR`.
        var erodedPSNR: Double
    }

    /// Returns true if the image has float components or a high-bit-depth representation
    /// that warrants an HDR comparison path.
    static func isHDR(_ image: CGImage) -> Bool {
        let bitmapInfo = image.bitmapInfo
        if bitmapInfo.contains(.floatComponents) {
            return true
        }
        if image.bitsPerComponent > 8 {
            return true
        }
        // Extended-range color spaces imply HDR-capable content even at 8-bit.
        if let cs = image.colorSpace, cs.name.map({ ($0 as String).contains("extended") }) == true {
            return true
        }
        return false
    }

    /// Compare two CGImages on the CPU and return both standard and edge-aware PSNR.
    ///
    /// The edge-aware variant applies a 3×3 morphological erosion (minimum filter) to the
    /// per-pixel squared-error map before averaging — any pixel with a zero-error neighbor is
    /// treated as zero. This suppresses single-pixel anti-aliasing halos along shape edges
    /// while preserving solid regions of error.
    ///
    /// Dispatches to an HDR (32-bit float, linear, peak=1.0) path when either input has
    /// float components, >8bpc, or an extended-range color space. Otherwise uses the
    /// standard 8-bit linearSRGB path (peak=255).
    func compareDetailed(_ lhs: CGImage, _ rhs: CGImage) throws -> DetailedResult {
        if Self.isHDR(lhs) || Self.isHDR(rhs) {
            return try compareDetailedHDR(lhs, rhs)
        }
        return try compareDetailedSDR(lhs, rhs)
    }

    /// HDR comparison path: draws both images into a 32-bit float extended-linear-sRGB
    /// context and computes PSNR with peak=1.0.
    private func compareDetailedHDR(_ lhs: CGImage, _ rhs: CGImage) throws -> DetailedResult {
        guard lhs.width == rhs.width, lhs.height == rhs.height else {
            throw TextureComparisonError.dimensionMismatch
        }

        let width = lhs.width
        let height = lhs.height
        let pixelCount = width * height
        let bytesPerPixel = 16 // RGBA, 4×Float32
        let bytesPerRow = width * bytesPerPixel
        let floatCount = pixelCount * 4

        guard let colorSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) else {
            throw TextureComparisonError.failedToCreateTexture
        }
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue
            | CGBitmapInfo.floatComponents.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue

        var pixelsA = [Float](repeating: 0, count: floatCount)
        var pixelsB = [Float](repeating: 0, count: floatCount)

        guard let contextA = CGContext(
            data: &pixelsA,
            width: width,
            height: height,
            bitsPerComponent: 32,
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
            bitsPerComponent: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw TextureComparisonError.failedToCreateTexture
        }

        contextA.draw(lhs, in: CGRect(x: 0, y: 0, width: width, height: height))
        contextB.draw(rhs, in: CGRect(x: 0, y: 0, width: width, height: height))

        var errorMap = [Double](repeating: 0, count: pixelCount)
        var sumSquaredDiff: Double = 0.0
        for i in 0..<pixelCount {
            let p = i * 4
            let dR = Double(pixelsA[p]) - Double(pixelsB[p])
            let dG = Double(pixelsA[p + 1]) - Double(pixelsB[p + 1])
            let dB = Double(pixelsA[p + 2]) - Double(pixelsB[p + 2])
            let dA = Double(pixelsA[p + 3]) - Double(pixelsB[p + 3])
            let sq = dR * dR + dG * dG + dB * dB + dA * dA
            errorMap[i] = sq
            sumSquaredDiff += sq
        }

        let erodedSum = Self.erodeErrorMap(errorMap, width: width, height: height, radius: erosionRadius)

        let divisor = Double(pixelCount * 4)
        let mse = sumSquaredDiff / divisor
        let erodedMSE = erodedSum / divisor
        let peak = 1.0
        let psnr = mse == 0 ? 120.0 : min(20.0 * log10(peak / sqrt(mse)), 120.0)
        let erodedPSNR = erodedMSE == 0 ? 120.0 : min(20.0 * log10(peak / sqrt(erodedMSE)), 120.0)
        return DetailedResult(psnr: psnr, erodedPSNR: erodedPSNR)
    }

    /// Sum of error-map values that survive `(2r+1)×(2r+1)` morphological erosion
    /// (shared by SDR and HDR paths). Border pixels within `r` of the edge are
    /// treated as having an implicit zero neighbor (conservative).
    private static func erodeErrorMap(_ errorMap: [Double], width: Int, height: Int, radius r: Int) -> Double {
        var erodedSum: Double = 0.0
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                let value = errorMap[idx]
                if value == 0 { continue }
                if x < r || y < r || x >= width - r || y >= height - r { continue }
                var anyZero = false
                neighborLoop: for dy in -r...r {
                    for dx in -r...r where dx != 0 || dy != 0 {
                        if errorMap[(y + dy) * width + (x + dx)] == 0 {
                            anyZero = true
                            break neighborLoop
                        }
                    }
                }
                if !anyZero { erodedSum += value }
            }
        }
        return erodedSum
    }

    private func compareDetailedSDR(_ lhs: CGImage, _ rhs: CGImage) throws -> DetailedResult {
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
        // (remainder of body unchanged; HDR dispatch happens in compareDetailed)

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

        let pixelCount = width * height

        // Per-pixel sum of squared channel differences (RGBA).
        var errorMap = [Double](repeating: 0, count: pixelCount)
        var sumSquaredDiff: Double = 0.0

        for i in 0..<pixelCount {
            let pixelIndex = i * bytesPerPixel

            let diffR = Double(pixelsA[pixelIndex]) - Double(pixelsB[pixelIndex])
            let diffG = Double(pixelsA[pixelIndex + 1]) - Double(pixelsB[pixelIndex + 1])
            let diffB = Double(pixelsA[pixelIndex + 2]) - Double(pixelsB[pixelIndex + 2])
            let diffA = Double(pixelsA[pixelIndex + 3]) - Double(pixelsB[pixelIndex + 3])

            let sq = diffR * diffR + diffG * diffG + diffB * diffB + diffA * diffA
            errorMap[i] = sq
            sumSquaredDiff += sq
        }

        let erodedSum = Self.erodeErrorMap(errorMap, width: width, height: height, radius: erosionRadius)

        let divisor = Double(pixelCount * 4)
        let mse = sumSquaredDiff / divisor
        let erodedMSE = erodedSum / divisor

        let psnr: Double = mse == 0 ? 120.0 : min(20.0 * log10(255.0 / sqrt(mse)), 120.0)
        let erodedPSNR: Double = erodedMSE == 0 ? 120.0 : min(20.0 * log10(255.0 / sqrt(erodedMSE)), 120.0)

        return DetailedResult(psnr: psnr, erodedPSNR: erodedPSNR)
    }

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
