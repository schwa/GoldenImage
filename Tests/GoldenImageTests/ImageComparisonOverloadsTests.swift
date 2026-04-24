import CoreGraphics
import CoreImage
import Foundation
@testable import GoldenImage
import ImageIO
import Metal
import SwiftUI
import Testing

@Suite("ImageComparison overloads")
internal struct ImageComparisonOverloadsTests {
    // MARK: - Helpers

    private func resourceURL(named name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources")
            .appendingPathComponent("\(name).png")
    }

    private func loadResourceImage(named name: String) throws -> CGImage {
        let url = resourceURL(named: name)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
            let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw TestError.failedToLoadImage(url.path)
        }
        return img
    }

    // MARK: - CGImage overload

    @Test
    func compareCGImage_identical() throws {
        let image = try loadResourceImage(named: "alpha_blend")
        let result = try ImageComparison().compare(image, image)
        #expect(result.psnr >= 120.0)
        #expect(result.isMatch)
    }

    @Test
    func differenceImageCGImage_identicalReturnsBlack() throws {
        let image = try loadResourceImage(named: "alpha_blend")
        let diff = try ImageComparison().differenceImage(image, image)

        #expect(diff.width == image.width)
        #expect(diff.height == image.height)

        // Sample the center pixel of the diff image - should be near zero (black) for identical images.
        let ctxBytes = diff.width
        var pixel: UInt8 = 0xFF
        guard let gray = CGColorSpace(name: CGColorSpace.linearGray) else {
            Issue.record("Failed to create grayscale colorspace")
            return
        }
        guard let ctx = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 1,
            space: gray,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            Issue.record("Failed to create sampling context")
            return
        }
        ctx.draw(diff, in: CGRect(x: -Double(ctxBytes) / 2, y: -Double(diff.height) / 2, width: Double(ctxBytes), height: Double(diff.height)))
        #expect(pixel == 0)
    }

    // MARK: - URL overload

    @Test
    func compareURL_identical() throws {
        let url = resourceURL(named: "alpha_blend")
        let result = try ImageComparison().compare(url, url)
        #expect(result.psnr >= 120.0)
    }

    @Test
    func differenceImageURL_identicalSizeMatches() throws {
        let url = resourceURL(named: "alpha_blend")
        let diff = try ImageComparison().differenceImage(url, url)
        let image = try loadResourceImage(named: "alpha_blend")
        #expect(diff.width == image.width)
        #expect(diff.height == image.height)
    }

    @Test
    func compareURL_missingFileThrows() {
        let bogus = URL(fileURLWithPath: "/tmp/__goldenimage_does_not_exist__.png")
        #expect(throws: TextureComparisonError.self) {
            _ = try ImageComparison().compare(bogus, bogus)
        }
        #expect(throws: TextureComparisonError.self) {
            _ = try ImageComparison().differenceImage(bogus, bogus)
        }
    }

    // MARK: - CIImage overload

    @Test
    func compareCIImage_identical() throws {
        let url = resourceURL(named: "alpha_blend")
        guard let ci = CIImage(contentsOf: url) else {
            Issue.record("Failed to load CIImage")
            return
        }
        let result = try ImageComparison().compare(ci, ci)
        #expect(result.psnr >= 120.0)
    }

    @Test
    func differenceImageCIImage_identical() throws {
        let url = resourceURL(named: "alpha_blend")
        guard let ci = CIImage(contentsOf: url) else {
            Issue.record("Failed to load CIImage")
            return
        }
        let diff = try ImageComparison().differenceImage(ci, ci)
        #expect(diff.width == Int(ci.extent.width))
        #expect(diff.height == Int(ci.extent.height))
    }

    // MARK: - SwiftUI Image overload

    @MainActor
    @Test
    func compareSwiftUIImage_identical() throws {
        let image = Image(systemName: "star.fill")
        let result = try ImageComparison().compare(image, image)
        #expect(result.psnr >= 120.0)
    }

    // MARK: - MTLTexture overload

    @Test
    func compareMTLTexture_identical() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw TestError.metalNotAvailable
        }
        let image = try loadResourceImage(named: "alpha_blend")
        let texture = try makeTexture(from: image, device: device)
        let result = try ImageComparison().compare(texture, texture)
        #expect(result.psnr >= 120.0)
    }

    @Test
    func compareMTLTexture_dimensionMismatchThrows() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw TestError.metalNotAvailable
        }
        let image = try loadResourceImage(named: "alpha_blend")
        let textureA = try makeTexture(from: image, device: device)

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: image.width + 1,
            height: image.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        guard let textureB = device.makeTexture(descriptor: descriptor) else {
            throw TestError.metalNotAvailable
        }

        #expect(throws: TextureComparisonError.self) {
            _ = try ImageComparison().compare(textureA, textureB)
        }
    }

    // MARK: - HDR / float path

    /// Build a 32-bit float extended-linear-sRGB CGImage filled with the given RGBA color.
    private func makeFloatImage(width: Int, height: Int, rgba: (Float, Float, Float, Float)) throws -> CGImage {
        guard let cs = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) else {
            throw TestError.failedToLoadImage("colorspace")
        }
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue
            | CGBitmapInfo.floatComponents.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        let pixelCount = width * height
        var pixels = [Float](repeating: 0, count: pixelCount * 4)
        for i in 0..<pixelCount {
            pixels[i * 4] = rgba.0
            pixels[i * 4 + 1] = rgba.1
            pixels[i * 4 + 2] = rgba.2
            pixels[i * 4 + 3] = rgba.3
        }
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 32,
            bytesPerRow: width * 16,
            space: cs,
            bitmapInfo: bitmapInfo
        ), let image = ctx.makeImage() else {
            throw TestError.failedToLoadImage("float ctx")
        }
        return image
    }

    @Test
    func hdrCompare_isDispatchedForFloatInputs() throws {
        let a = try makeFloatImage(width: 32, height: 32, rgba: (0.5, 0.5, 0.5, 1.0))
        #expect(CPUCompare.isHDR(a))
    }

    @Test
    func hdrCompare_identicalFloatImagesMatch() throws {
        let a = try makeFloatImage(width: 32, height: 32, rgba: (2.5, 1.8, 0.3, 1.0)) // HDR overbright
        let result = try ImageComparison().compare(a, a)
        #expect(result.psnr >= 120.0)
        #expect(result.erodedPSNR ?? 0 >= 120.0)
    }

    @Test
    func hdrCompare_overbrightDifferencePenalized() throws {
        // Two HDR images with a small but real overbright mismatch.
        let a = try makeFloatImage(width: 32, height: 32, rgba: (1.0, 1.0, 1.0, 1.0))
        let b = try makeFloatImage(width: 32, height: 32, rgba: (1.1, 1.0, 1.0, 1.0)) // 0.1 red delta
        let result = try ImageComparison().compare(a, b)

        // rmse across 4 channels = sqrt(0.01/4) = 0.05, PSNR = 20*log10(1/0.05) ≈ 26.02 dB
        #expect((24.0...28.0).contains(result.psnr))
        #expect(result.psnr < 120.0)
    }

    /// Load a CGImage from a resource file with a non-default extension (e.g. .exr).
    private func loadResource(named name: String, ext: String) throws -> CGImage {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources")
            .appendingPathComponent("\(name).\(ext)")
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
            let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw TestError.failedToLoadImage(url.path)
        }
        return img
    }

    @Test
    func hdrCompare_realEXRFixturesIdentical() throws {
        let a = try loadResource(named: "hdr_a", ext: "exr")
        #expect(CPUCompare.isHDR(a))
        let result = try ImageComparison().compare(a, a)
        #expect(result.psnr >= 120.0)
        #expect(result.erodedPSNR ?? 0 >= 120.0)
    }

    @Test
    func hdrCompare_realEXRFixturesDifferentSun() throws {
        // hdr_a vs hdr_b differ only inside a 16x16 "sun" region: red channel 8.0 vs 7.0
        // (overbright HDR values). The error is solid (not edge-only), so PSNR should be
        // measurably below 120 and eroded PSNR should track it closely.
        let a = try loadResource(named: "hdr_a", ext: "exr")
        let b = try loadResource(named: "hdr_b", ext: "exr")
        #expect(CPUCompare.isHDR(a))
        #expect(CPUCompare.isHDR(b))

        let result = try ImageComparison().compare(a, b)
        guard let eroded = result.erodedPSNR else {
            Issue.record("erodedPSNR missing for HDR CGImage path")
            return
        }

        print("hdr fixtures - PSNR: \(result.psnr) dB, eroded: \(eroded) dB")

        // Real, solid HDR difference — must be a finite (non-120) score.
        #expect(result.psnr < 30.0)
        #expect(result.psnr > 0.0)
        // Solid 16x16 region: erosion only nibbles the 1px border, so eroded ≈ psnr.
        #expect(eroded < result.psnr + 2.0)
    }

    @Test
    func hdrCompare_dimensionMismatchThrows() throws {
        let a = try makeFloatImage(width: 32, height: 32, rgba: (1.0, 1.0, 1.0, 1.0))
        let b = try makeFloatImage(width: 16, height: 32, rgba: (1.0, 1.0, 1.0, 1.0))
        #expect(throws: TextureComparisonError.self) {
            _ = try ImageComparison().compare(a, b)
        }
    }

    // MARK: - CPU error paths

    @Test
    func cpuCompare_dimensionMismatchThrows() throws {
        let imageA = try loadResourceImage(named: "alpha_blend")

        // Create a smaller image with the same colorspace.
        let width = max(1, imageA.width / 2)
        let height = max(1, imageA.height / 2)
        guard let colorSpace = imageA.colorSpace,
            let ctx = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            let imageB = ctx.makeImage() else {
            Issue.record("Failed to create mismatched image")
            return
        }

        #expect(throws: TextureComparisonError.self) {
            _ = try CPUCompare().compare(imageA, imageB)
        }
        #expect(throws: TextureComparisonError.self) {
            _ = try CPUCompare().differenceImage(imageA, imageB)
        }
    }

    @Test
    func cpuCompare_colorSpaceMismatchThrows() throws {
        let imageA = try loadResourceImage(named: "alpha_blend")
        let width = imageA.width
        let height = imageA.height

        // Create a same-size image in a different color space.
        guard let otherSpace = CGColorSpace(name: CGColorSpace.displayP3),
            let ctx = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: otherSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            let imageB = ctx.makeImage() else {
            Issue.record("Failed to create differently-colored image")
            return
        }

        #expect(throws: TextureComparisonError.self) {
            _ = try CPUCompare().compare(imageA, imageB)
        }
        #expect(throws: TextureComparisonError.self) {
            _ = try CPUCompare().differenceImage(imageA, imageB)
        }
    }
}
