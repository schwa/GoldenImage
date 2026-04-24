import CoreGraphics
import Foundation
@testable import GoldenImage
import ImageIO
import Metal
import SwiftUI
import Testing

internal struct ImageCompareTests {
    // MARK: - Helper Methods

    /// Load a CGImage from an EXR file
    private func loadImage(named name: String) throws -> CGImage {
        let url = TestImageGenerator.imageURL(named: name)

        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw TestError.failedToLoadImage(url.path)
        }

        return cgImage
    }

    /// Load a CGImage from the Resources directory
    private func loadResourceImage(named name: String) throws -> CGImage {
        let resourcesURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources")
            .appendingPathComponent("\(name).png")

        guard let imageSource = CGImageSourceCreateWithURL(resourcesURL as CFURL, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw TestError.failedToLoadImage(resourcesURL.path)
        }

        return cgImage
    }

    /// Compare two images using CPU method and return PSNR
    private func compareCPU(imageA: CGImage, imageB: CGImage, nameA: String, nameB: String) throws -> Double {
        let comparison = ImageComparison()
        let result = try comparison.compare(imageA, imageB)
        return result.psnr
    }

    /// Compare two images using GPU method and return PSNR
    private func compareGPU(imageA: CGImage, imageB: CGImage) throws -> Double {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw TestError.metalNotAvailable
        }
        let textureA = try makeTexture(from: imageA, device: device)
        let textureB = try makeTexture(from: imageB, device: device)

        let comparison = ImageComparison()
        let result = try comparison.compare(textureA, textureB)
        return result.psnr
    }

    /// Log CPU and GPU PSNR results. Also asserts that the two agree within 1 dB —
    /// this is the primary oracle check that replaces the previous ImageMagick comparison.
    private func logComparison(name: String, cpu: Double, gpu: Double, sourceLocation: Testing.SourceLocation = #_sourceLocation) {
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...3))
        print("\(name) - CPU: \(cpu.formatted(format)) dB, GPU: \(gpu.formatted(format)) dB")
        // CPU and GPU must agree to within 1 dB for any non-identical image.
        // (For identical images both saturate at 120 dB so the check is trivially true.)
        #expect(abs(cpu - gpu) <= 1.0, "CPU/GPU PSNR disagree by more than 1 dB", sourceLocation: sourceLocation)
    }

    // MARK: - Tests

    @Test
    func testIdenticalImages() async throws {
        try await MainActor.run {
            try TestImageGenerator.generate(name: "identical_a") {
                Canvas { context, size in
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.blue))
                }
            }
            try TestImageGenerator.generate(name: "identical_b") {
                Canvas { context, size in
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.blue))
                }
            }
        }

        let imageA = try loadImage(named: "identical_a")
        let imageB = try loadImage(named: "identical_b")

        let cpuPSNR = try compareCPU(imageA: imageA, imageB: imageB, nameA: "identical_a", nameB: "identical_b")
        let gpuPSNR = try compareGPU(imageA: imageA, imageB: imageB)

        logComparison(name: "identical", cpu: cpuPSNR, gpu: gpuPSNR)

        #expect(cpuPSNR >= 120.0)
        #expect(gpuPSNR >= 120.0)
    }

    @Test
    func testDifferentImages() async throws {
        try await MainActor.run {
            try TestImageGenerator.generate(name: "different_a") {
                Canvas { context, size in
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.blue))
                }
            }
            try TestImageGenerator.generate(name: "different_b") {
                Canvas { context, size in
                    let rect = CGRect(origin: .zero, size: size)
                    context.fill(Path(rect), with: .color(.red))
                    let circlePath = Path(ellipseIn: CGRect(x: rect.midX - 50, y: rect.midY - 50, width: 100, height: 100))
                    context.fill(circlePath, with: .color(.yellow))
                }
            }
        }

        let imageA = try loadImage(named: "different_a")
        let imageB = try loadImage(named: "different_b")

        let cpuPSNR = try compareCPU(imageA: imageA, imageB: imageB, nameA: "different_a", nameB: "different_b")
        let gpuPSNR = try compareGPU(imageA: imageA, imageB: imageB)

        logComparison(name: "different", cpu: cpuPSNR, gpu: gpuPSNR)

        #expect(cpuPSNR < 7.0)
        #expect(gpuPSNR < 7.0)
    }

    @Test
    func testAlmostIdenticalImages() async throws {
        try await MainActor.run {
            try TestImageGenerator.generate(name: "almost_a") {
                Canvas { context, size in
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.blue))
                }
            }
            try TestImageGenerator.generate(name: "almost_b") {
                Canvas { context, size in
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.blue))
                    let dotPath = Path(ellipseIn: CGRect(x: 10, y: 10, width: 2, height: 2))
                    context.fill(dotPath, with: .color(.white.opacity(0.1)))
                }
            }
        }

        let imageA = try loadImage(named: "almost_a")
        let imageB = try loadImage(named: "almost_b")

        let cpuPSNR = try compareCPU(imageA: imageA, imageB: imageB, nameA: "almost_a", nameB: "almost_b")
        let gpuPSNR = try compareGPU(imageA: imageA, imageB: imageB)

        logComparison(name: "almost", cpu: cpuPSNR, gpu: gpuPSNR)

        #expect((67.0...78.0).contains(cpuPSNR))
        #expect((67.0...78.0).contains(gpuPSNR))
    }

    // MARK: - Alpha/Transparency Tests

    @Test
    func testIdenticalWithAlpha() async throws {
        try await MainActor.run {
            try TestImageGenerator.generate(name: "alpha_identical_a") {
                Canvas { context, size in
                    let rect = CGRect(origin: .zero, size: size)
                    context.fill(Path(rect), with: .color(.blue.opacity(0.5)))
                }
            }
            try TestImageGenerator.generate(name: "alpha_identical_b") {
                Canvas { context, size in
                    let rect = CGRect(origin: .zero, size: size)
                    context.fill(Path(rect), with: .color(.blue.opacity(0.5)))
                }
            }
        }

        let imageA = try loadImage(named: "alpha_identical_a")
        let imageB = try loadImage(named: "alpha_identical_b")

        let cpuPSNR = try compareCPU(imageA: imageA, imageB: imageB, nameA: "alpha_identical_a", nameB: "alpha_identical_b")
        let gpuPSNR = try compareGPU(imageA: imageA, imageB: imageB)

        logComparison(name: "alpha_identical", cpu: cpuPSNR, gpu: gpuPSNR)

        #expect(cpuPSNR >= 120.0)
        #expect(gpuPSNR >= 120.0)
    }

    @Test
    func testDifferentAlpha() async throws {
        try await MainActor.run {
            try TestImageGenerator.generate(name: "alpha_different_a") {
                Canvas { context, size in
                    let rect = CGRect(origin: .zero, size: size)
                    context.fill(Path(rect), with: .color(.blue.opacity(1.0)))
                }
            }
            try TestImageGenerator.generate(name: "alpha_different_b") {
                Canvas { context, size in
                    let rect = CGRect(origin: .zero, size: size)
                    context.fill(Path(rect), with: .color(.blue.opacity(0.2)))
                }
            }
        }

        let imageA = try loadImage(named: "alpha_different_a")
        let imageB = try loadImage(named: "alpha_different_b")

        let cpuPSNR = try compareCPU(imageA: imageA, imageB: imageB, nameA: "alpha_different_a", nameB: "alpha_different_b")
        let gpuPSNR = try compareGPU(imageA: imageA, imageB: imageB)

        logComparison(name: "alpha_different", cpu: cpuPSNR, gpu: gpuPSNR)

        #expect((3.0...13.0).contains(cpuPSNR))
        #expect((3.0...13.0).contains(gpuPSNR))
    }

    @Test
    func testAlphaGradient() async throws {
        try await MainActor.run {
            try TestImageGenerator.generate(name: "alpha_gradient_a") {
                Canvas { context, size in
                    let gradient = Gradient(colors: [
                        Color.blue.opacity(0.0),
                        Color.blue.opacity(1.0)
                    ])
                    let rect = CGRect(origin: .zero, size: size)
                    context.fill(Path(rect), with: .linearGradient(
                        gradient,
                        startPoint: .zero,
                        endPoint: CGPoint(x: size.width, y: 0)
                    ))
                }
            }
            try TestImageGenerator.generate(name: "alpha_gradient_b") {
                Canvas { context, size in
                    // Stepped gradient
                    let steps = 5
                    let stepWidth = size.width / CGFloat(steps)
                    for i in 0..<steps {
                        let opacity = Double(i) / Double(steps - 1)
                        let rect = CGRect(x: CGFloat(i) * stepWidth, y: 0, width: stepWidth, height: size.height)
                        context.fill(Path(rect), with: .color(.blue.opacity(opacity)))
                    }
                }
            }
        }

        let imageA = try loadImage(named: "alpha_gradient_a")
        let imageB = try loadImage(named: "alpha_gradient_b")

        let cpuPSNR = try compareCPU(imageA: imageA, imageB: imageB, nameA: "alpha_gradient_a", nameB: "alpha_gradient_b")
        let gpuPSNR = try compareGPU(imageA: imageA, imageB: imageB)

        logComparison(name: "alpha_gradient", cpu: cpuPSNR, gpu: gpuPSNR)

        #expect((20...25.0).contains(cpuPSNR))
        #expect((10...25.0).contains(gpuPSNR))
    }

    // MARK: - Gradient Tests

    @Test
    func testIdenticalGradients() async throws {
        try await MainActor.run {
            try TestImageGenerator.generate(name: "gradient_identical_a") {
                Canvas { context, size in
                    let gradient = Gradient(colors: [Color.blue, Color.red])
                    let rect = CGRect(origin: .zero, size: size)
                    context.fill(Path(rect), with: .linearGradient(
                        gradient,
                        startPoint: .zero,
                        endPoint: CGPoint(x: size.width, y: 0)
                    ))
                }
            }
            try TestImageGenerator.generate(name: "gradient_identical_b") {
                Canvas { context, size in
                    let gradient = Gradient(colors: [Color.blue, Color.red])
                    let rect = CGRect(origin: .zero, size: size)
                    context.fill(Path(rect), with: .linearGradient(
                        gradient,
                        startPoint: .zero,
                        endPoint: CGPoint(x: size.width, y: 0)
                    ))
                }
            }
        }

        let imageA = try loadImage(named: "gradient_identical_a")
        let imageB = try loadImage(named: "gradient_identical_b")

        let cpuPSNR = try compareCPU(imageA: imageA, imageB: imageB, nameA: "gradient_identical_a", nameB: "gradient_identical_b")
        let gpuPSNR = try compareGPU(imageA: imageA, imageB: imageB)

        logComparison(name: "gradient_identical", cpu: cpuPSNR, gpu: gpuPSNR)

        #expect(cpuPSNR >= 120.0)
        #expect(gpuPSNR >= 120.0)
    }

    @Test
    func testDifferentGradientDirections() async throws {
        try await MainActor.run {
            try TestImageGenerator.generate(name: "gradient_direction_a") {
                Canvas { context, size in
                    let gradient = Gradient(colors: [Color.blue, Color.red])
                    let rect = CGRect(origin: .zero, size: size)
                    context.fill(Path(rect), with: .linearGradient(
                        gradient,
                        startPoint: .zero,
                        endPoint: CGPoint(x: size.width, y: 0)
                    ))
                }
            }
            try TestImageGenerator.generate(name: "gradient_direction_b") {
                Canvas { context, size in
                    let gradient = Gradient(colors: [Color.blue, Color.red])
                    let rect = CGRect(origin: .zero, size: size)
                    context.fill(Path(rect), with: .linearGradient(
                        gradient,
                        startPoint: .zero,
                        endPoint: CGPoint(x: 0, y: size.height)
                    ))
                }
            }
        }

        let imageA = try loadImage(named: "gradient_direction_a")
        let imageB = try loadImage(named: "gradient_direction_b")

        let cpuPSNR = try compareCPU(imageA: imageA, imageB: imageB, nameA: "gradient_direction_a", nameB: "gradient_direction_b")
        let gpuPSNR = try compareGPU(imageA: imageA, imageB: imageB)

        logComparison(name: "gradient_direction", cpu: cpuPSNR, gpu: gpuPSNR)

        #expect((4.0...15.0).contains(cpuPSNR))
        #expect((4.0...15.0).contains(gpuPSNR))
    }

    @Test
    func testSmoothVsBandedGradient() async throws {
        try await MainActor.run {
            try TestImageGenerator.generate(name: "gradient_smooth_a") {
                Canvas { context, size in
                    let gradient = Gradient(colors: [Color.blue, Color.red])
                    let rect = CGRect(origin: .zero, size: size)
                    context.fill(Path(rect), with: .linearGradient(
                        gradient,
                        startPoint: .zero,
                        endPoint: CGPoint(x: size.width, y: 0)
                    ))
                }
            }
            try TestImageGenerator.generate(name: "gradient_smooth_b") {
                Canvas { context, size in
                    // Posterized gradient with 5 bands
                    let bands = 5
                    let bandWidth = size.width / CGFloat(bands)
                    for i in 0..<bands {
                        let t = Double(i) / Double(bands - 1)
                        let color = Color(
                            red: (1 - t) * 0 + t * 1,
                            green: 0,
                            blue: (1 - t) * 1 + t * 0
                        )
                        let rect = CGRect(x: CGFloat(i) * bandWidth, y: 0, width: bandWidth, height: size.height)
                        context.fill(Path(rect), with: .color(color))
                    }
                }
            }
        }

        let imageA = try loadImage(named: "gradient_smooth_a")
        let imageB = try loadImage(named: "gradient_smooth_b")

        let cpuPSNR = try compareCPU(imageA: imageA, imageB: imageB, nameA: "gradient_smooth_a", nameB: "gradient_smooth_b")
        let gpuPSNR = try compareGPU(imageA: imageA, imageB: imageB)

        logComparison(name: "gradient_smooth", cpu: cpuPSNR, gpu: gpuPSNR)

        #expect((12.0...23.0).contains(cpuPSNR))
        #expect((12.0...23.0).contains(gpuPSNR))
    }

    // MARK: - Size Tests

    @Test
    func testSmallIdenticalImages() async throws {
        try await MainActor.run {
            try TestImageGenerator.generate(name: "small_identical_a", size: CGSize(width: 64, height: 64)) {
                Canvas { context, size in
                    let rect = CGRect(origin: .zero, size: size)
                    context.fill(Path(rect), with: .color(.blue))
                }
            }
            try TestImageGenerator.generate(name: "small_identical_b", size: CGSize(width: 64, height: 64)) {
                Canvas { context, size in
                    let rect = CGRect(origin: .zero, size: size)
                    context.fill(Path(rect), with: .color(.blue))
                }
            }
        }

        let imageA = try loadImage(named: "small_identical_a")
        let imageB = try loadImage(named: "small_identical_b")

        let cpuPSNR = try compareCPU(imageA: imageA, imageB: imageB, nameA: "small_identical_a", nameB: "small_identical_b")
        let gpuPSNR = try compareGPU(imageA: imageA, imageB: imageB)

        logComparison(name: "small_identical", cpu: cpuPSNR, gpu: gpuPSNR)

        #expect(cpuPSNR >= 120.0)
        #expect(gpuPSNR >= 120.0)
    }

    @Test
    func testLargeIdenticalImages() async throws {
        try await MainActor.run {
            try TestImageGenerator.generate(name: "large_identical_a", size: CGSize(width: 1_024, height: 1_024)) {
                Canvas { context, size in
                    let rect = CGRect(origin: .zero, size: size)
                    context.fill(Path(rect), with: .color(.blue))
                }
            }
            try TestImageGenerator.generate(name: "large_identical_b", size: CGSize(width: 1_024, height: 1_024)) {
                Canvas { context, size in
                    let rect = CGRect(origin: .zero, size: size)
                    context.fill(Path(rect), with: .color(.blue))
                }
            }
        }

        let imageA = try loadImage(named: "large_identical_a")
        let imageB = try loadImage(named: "large_identical_b")

        let cpuPSNR = try compareCPU(imageA: imageA, imageB: imageB, nameA: "large_identical_a", nameB: "large_identical_b")
        let gpuPSNR = try compareGPU(imageA: imageA, imageB: imageB)

        logComparison(name: "large_identical", cpu: cpuPSNR, gpu: gpuPSNR)

        #expect(cpuPSNR >= 120.0)
        #expect(gpuPSNR >= 120.0)
    }

    @Test
    func testNonSquareIdenticalImages() async throws {
        try await MainActor.run {
            try TestImageGenerator.generate(name: "nonsquare_identical_a", size: CGSize(width: 512, height: 256)) {
                Canvas { context, size in
                    let rect = CGRect(origin: .zero, size: size)
                    context.fill(Path(rect), with: .color(.blue))
                }
            }
            try TestImageGenerator.generate(name: "nonsquare_identical_b", size: CGSize(width: 512, height: 256)) {
                Canvas { context, size in
                    let rect = CGRect(origin: .zero, size: size)
                    context.fill(Path(rect), with: .color(.blue))
                }
            }
        }

        let imageA = try loadImage(named: "nonsquare_identical_a")
        let imageB = try loadImage(named: "nonsquare_identical_b")

        let cpuPSNR = try compareCPU(imageA: imageA, imageB: imageB, nameA: "nonsquare_identical_a", nameB: "nonsquare_identical_b")
        let gpuPSNR = try compareGPU(imageA: imageA, imageB: imageB)

        logComparison(name: "nonsquare_identical", cpu: cpuPSNR, gpu: gpuPSNR)

        #expect(cpuPSNR >= 120.0)
        #expect(gpuPSNR >= 120.0)
    }

    // MARK: - Edge Case Tests

    @Test
    func testSinglePixelDifferentLocations() async throws {
        try await MainActor.run {
            try TestImageGenerator.generate(name: "pixel_corner_a") {
                Canvas { context, size in
                    let rect = CGRect(origin: .zero, size: size)
                    context.fill(Path(rect), with: .color(.blue))
                    // White pixel at corner
                    let pixelPath = Path(CGRect(x: 0, y: 0, width: 1, height: 1))
                    context.fill(pixelPath, with: .color(.white))
                }
            }
            try TestImageGenerator.generate(name: "pixel_corner_b") {
                Canvas { context, size in
                    let rect = CGRect(origin: .zero, size: size)
                    context.fill(Path(rect), with: .color(.blue))
                    // White pixel at center
                    let pixelPath = Path(CGRect(x: size.width / 2, y: size.height / 2, width: 1, height: 1))
                    context.fill(pixelPath, with: .color(.white))
                }
            }
        }

        let imageA = try loadImage(named: "pixel_corner_a")
        let imageB = try loadImage(named: "pixel_corner_b")

        let cpuPSNR = try compareCPU(imageA: imageA, imageB: imageB, nameA: "pixel_corner_a", nameB: "pixel_corner_b")
        let gpuPSNR = try compareGPU(imageA: imageA, imageB: imageB)

        logComparison(name: "pixel_corner", cpu: cpuPSNR, gpu: gpuPSNR)

        #expect((42.0...53.0).contains(cpuPSNR))
        #expect((42.0...53.0).contains(gpuPSNR))
    }

    // NOTE: Removed "Clean vs noisy" test - SwiftUI Canvas doesn't render per-pixel noise well
    // The generated images were identical despite noise code. Would need a different approach
    // to generate actual noisy images (perhaps loading from a pre-made noisy image file).

    @Test
    func testCheckerboardPatterns() async throws {
        try await MainActor.run {
            try TestImageGenerator.generate(name: "checker_8x8_a") {
                Canvas { context, size in
                    let tileSize = size.width / 8
                    for row in 0..<8 {
                        for col in 0..<8 {
                            let color = (row + col).isMultiple(of: 2) ? Color.blue : Color.red
                            let rect = CGRect(x: CGFloat(col) * tileSize, y: CGFloat(row) * tileSize, width: tileSize, height: tileSize)
                            context.fill(Path(rect), with: .color(color))
                        }
                    }
                }
            }
            try TestImageGenerator.generate(name: "checker_8x8_b") {
                Canvas { context, size in
                    let tileSize = size.width / 16
                    for row in 0..<16 {
                        for col in 0..<16 {
                            let color = (row + col).isMultiple(of: 2) ? Color.blue : Color.red
                            let rect = CGRect(x: CGFloat(col) * tileSize, y: CGFloat(row) * tileSize, width: tileSize, height: tileSize)
                            context.fill(Path(rect), with: .color(color))
                        }
                    }
                }
            }
        }

        let imageA = try loadImage(named: "checker_8x8_a")
        let imageB = try loadImage(named: "checker_8x8_b")

        let cpuPSNR = try compareCPU(imageA: imageA, imageB: imageB, nameA: "checker_8x8_a", nameB: "checker_8x8_b")
        let gpuPSNR = try compareGPU(imageA: imageA, imageB: imageB)

        logComparison(name: "checker_8x8", cpu: cpuPSNR, gpu: gpuPSNR)

        #expect(cpuPSNR < 10.0)
        #expect(gpuPSNR < 10.0)
    }

    // MARK: - Real-World Image Tests

    // MARK: - Edge-aware PSNR

    @Test
    func testErodedPSNR_identicalImages() throws {
        let image = try loadResourceImage(named: "alpha_blend")
        let result = try ImageComparison().compare(image, image)
        #expect(result.psnr >= 120.0)
        #expect(result.erodedPSNR ?? 0 >= 120.0)
    }

    @Test
    func testErodedPSNR_doesNotHideObviousDifferences() async throws {
        // For genuine, non-edge differences the eroded PSNR should stay low
        // — erosion must not paper over solid regions of mismatch.
        try await MainActor.run {
            try TestImageGenerator.generate(name: "eroded_diff_a") {
                Canvas { context, size in
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.blue))
                }
            }
            try TestImageGenerator.generate(name: "eroded_diff_b") {
                Canvas { context, size in
                    let rect = CGRect(origin: .zero, size: size)
                    context.fill(Path(rect), with: .color(.red))
                    let circlePath = Path(ellipseIn: CGRect(x: rect.midX - 50, y: rect.midY - 50, width: 100, height: 100))
                    context.fill(circlePath, with: .color(.yellow))
                }
            }
        }

        let imageA = try loadImage(named: "eroded_diff_a")
        let imageB = try loadImage(named: "eroded_diff_b")

        let result = try ImageComparison().compare(imageA, imageB)
        guard let erodedPSNR = result.erodedPSNR else {
            Issue.record("erodedPSNR should be populated for CGImage comparisons")
            return
        }

        print("eroded_diff (obvious) - PSNR: \(result.psnr) dB, eroded: \(erodedPSNR) dB")

        // Obvious difference: both should remain low. Guard against false positives.
        #expect(result.psnr < 10.0)
        #expect(erodedPSNR < 15.0)
    }

    @Test
    func testErodedPSNR_checkerboardStaysLow() async throws {
        // Checkerboard: every error pixel has error neighbors (no zero-error neighbors),
        // so erosion should barely change the score.
        try await MainActor.run {
            try TestImageGenerator.generate(name: "eroded_checker_a") {
                Canvas { context, size in
                    let tileSize = size.width / 8
                    for row in 0..<8 {
                        for col in 0..<8 {
                            let color = (row + col).isMultiple(of: 2) ? Color.blue : Color.red
                            let rect = CGRect(x: CGFloat(col) * tileSize, y: CGFloat(row) * tileSize, width: tileSize, height: tileSize)
                            context.fill(Path(rect), with: .color(color))
                        }
                    }
                }
            }
            try TestImageGenerator.generate(name: "eroded_checker_b") {
                Canvas { context, size in
                    let tileSize = size.width / 16
                    for row in 0..<16 {
                        for col in 0..<16 {
                            let color = (row + col).isMultiple(of: 2) ? Color.blue : Color.red
                            let rect = CGRect(x: CGFloat(col) * tileSize, y: CGFloat(row) * tileSize, width: tileSize, height: tileSize)
                            context.fill(Path(rect), with: .color(color))
                        }
                    }
                }
            }
        }

        let imageA = try loadImage(named: "eroded_checker_a")
        let imageB = try loadImage(named: "eroded_checker_b")

        let result = try ImageComparison().compare(imageA, imageB)
        guard let erodedPSNR = result.erodedPSNR else {
            Issue.record("erodedPSNR should be populated for CGImage comparisons")
            return
        }

        print("eroded_checker - PSNR: \(result.psnr) dB, eroded: \(erodedPSNR) dB")

        // Dense solid regions of error — erosion should not significantly inflate the score.
        #expect(erodedPSNR < result.psnr + 3.0)
    }

    @Test
    func testErodedPSNR_singlePixelDifferenceIsSuppressed() async throws {
        // Isolated single-pixel differences (surrounded by matching pixels) are exactly
        // what erosion is designed to discard.
        try await MainActor.run {
            try TestImageGenerator.generate(name: "eroded_pixel_a") {
                Canvas { context, size in
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.blue))
                }
            }
            try TestImageGenerator.generate(name: "eroded_pixel_b") {
                Canvas { context, size in
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.blue))
                    let pixelPath = Path(CGRect(x: size.width / 2, y: size.height / 2, width: 1, height: 1))
                    context.fill(pixelPath, with: .color(.white))
                }
            }
        }

        let imageA = try loadImage(named: "eroded_pixel_a")
        let imageB = try loadImage(named: "eroded_pixel_b")

        let result = try ImageComparison().compare(imageA, imageB)
        guard let erodedPSNR = result.erodedPSNR else {
            Issue.record("erodedPSNR should be populated for CGImage comparisons")
            return
        }

        print("eroded_single_pixel - PSNR: \(result.psnr) dB, eroded: \(erodedPSNR) dB")

        // The lone pixel contributes a finite drop to PSNR; eroding it wipes the error entirely.
        #expect(result.psnr < 100.0)
        #expect(erodedPSNR >= 120.0)
    }

    @Test
    func testErodedPSNR_blankVsCircleStaysLow() async throws {
        // Blank image vs. image with a solid circle: the circle interior is a large
        // solid region of error. Erosion should strip the 1px AA ring but leave the
        // interior intact — eroded PSNR should stay close to the baseline PSNR.
        try await MainActor.run {
            try TestImageGenerator.generate(name: "eroded_blank") {
                Canvas { context, size in
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                }
            }
            try TestImageGenerator.generate(name: "eroded_circle") {
                Canvas { context, size in
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                    let rect = CGRect(origin: .zero, size: size)
                    let circle = Path(ellipseIn: CGRect(x: rect.midX - 100, y: rect.midY - 100, width: 200, height: 200))
                    context.fill(circle, with: .color(.red))
                }
            }
        }

        let imageA = try loadImage(named: "eroded_blank")
        let imageB = try loadImage(named: "eroded_circle")

        let result = try ImageComparison().compare(imageA, imageB)
        guard let erodedPSNR = result.erodedPSNR else {
            Issue.record("erodedPSNR should be populated for CGImage comparisons")
            return
        }

        print("eroded_blank_vs_circle - PSNR: \(result.psnr) dB, eroded: \(erodedPSNR) dB")

        // Circle is a clear visual difference — PSNR should be low and erosion must
        // not inflate it significantly. The interior area is orders of magnitude larger
        // than the 1px AA ring, so the two values should be within ~1 dB of each other.
        #expect(result.psnr < 25.0)
        #expect(erodedPSNR < result.psnr + 2.0)
    }

    @Test
    func testErodedPSNR_thinStrokeSweep() async throws {
        // Characterize how erosion affects strokes of decreasing width. Thin strokes
        // are the edge case: at ~1pt the stroke is barely wider than the erosion kernel.
        for width in [1.0, 2.0, 3.0, 6.0] as [CGFloat] {
            let nameA = "eroded_sweep_blank_\(Int(width))"
            let nameB = "eroded_sweep_stroke_\(Int(width))"
            try await MainActor.run {
                try TestImageGenerator.generate(name: nameA) {
                    Canvas { context, size in
                        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                    }
                }
                try TestImageGenerator.generate(name: nameB) {
                    Canvas { context, size in
                        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                        let rect = CGRect(origin: .zero, size: size)
                        let circle = Path(ellipseIn: CGRect(x: rect.midX - 100, y: rect.midY - 100, width: 200, height: 200))
                        context.stroke(circle, with: .color(.red), lineWidth: width)
                    }
                }
            }
            let imageA = try loadImage(named: nameA)
            let imageB = try loadImage(named: nameB)
            let result = try ImageComparison().compare(imageA, imageB)
            let eroded = result.erodedPSNR ?? .nan
            print("eroded_sweep stroke=\(width)pt - PSNR: \(result.psnr) dB, eroded: \(eroded) dB (delta: \(eroded - result.psnr))")
        }
    }

    @Test
    func testErodedPSNR_blankVsStrokedCircleStaysLow() async throws {
        // Blank vs. a stroked circle (thin ring) — the error is a curved band only a few
        // pixels wide. Erosion may nibble the edges but the ring's core should survive.
        try await MainActor.run {
            try TestImageGenerator.generate(name: "eroded_blank_stroke") {
                Canvas { context, size in
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                }
            }
            try TestImageGenerator.generate(name: "eroded_stroked_circle") {
                Canvas { context, size in
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                    let rect = CGRect(origin: .zero, size: size)
                    let circle = Path(ellipseIn: CGRect(x: rect.midX - 100, y: rect.midY - 100, width: 200, height: 200))
                    context.stroke(circle, with: .color(.red), lineWidth: 6)
                }
            }
        }

        let imageA = try loadImage(named: "eroded_blank_stroke")
        let imageB = try loadImage(named: "eroded_stroked_circle")

        let result = try ImageComparison().compare(imageA, imageB)
        guard let erodedPSNR = result.erodedPSNR else {
            Issue.record("erodedPSNR should be populated for CGImage comparisons")
            return
        }

        print("eroded_blank_vs_stroked_circle - PSNR: \(result.psnr) dB, eroded: \(erodedPSNR) dB")

        // A 6pt stroke is clearly visible; the ring's interior pixels have ring-neighbors,
        // so most of the error survives erosion. Expect only a small inflation.
        #expect(result.psnr < 40.0)
        #expect(erodedPSNR < result.psnr + 4.0)
    }

    @Test
    func testErodedPSNR_ignoresAAHalos() throws {
        // Two rasterizations of the same artwork that differ only by ~1px AA along edges.
        // Standard PSNR is pulled down by the edge noise; eroded PSNR should be much higher.
        let imageA = try loadResourceImage(named: "edge_aa_a")
        let imageB = try loadResourceImage(named: "edge_aa_b")

        let result = try ImageComparison().compare(imageA, imageB)
        guard let erodedPSNR = result.erodedPSNR else {
            Issue.record("erodedPSNR should be populated for CGImage comparisons")
            return
        }

        print("edge_aa - PSNR: \(result.psnr) dB, eroded: \(erodedPSNR) dB")

        // Sanity: the baseline PSNR is in the low 30s-40s range due to AA edge noise.
        #expect(result.psnr < 60.0)
        // Edge-aware PSNR should be noticeably higher — at least 10 dB improvement.
        #expect(erodedPSNR >= result.psnr + 10.0)
    }

    @Test
    func testAlphaBlendVsReference() throws {
        let imageA = try loadResourceImage(named: "alpha_blend")
        let imageB = try loadResourceImage(named: "alpha_reference")

        let cpuPSNR = try compareCPU(imageA: imageA, imageB: imageB, nameA: "alpha_blend", nameB: "alpha_reference")
        let gpuPSNR = try compareGPU(imageA: imageA, imageB: imageB)

        logComparison(name: "alpha_blend_vs_reference", cpu: cpuPSNR, gpu: gpuPSNR)

        // Images are identical - expect perfect PSNR of 120 dB
        #expect(cpuPSNR >= 120.0)
        #expect(gpuPSNR >= 120.0)
    }
}

internal enum TestError: Error {
    case failedToLoadImage(String)
    case metalNotAvailable
    case imageMagickFailed(String)
}
