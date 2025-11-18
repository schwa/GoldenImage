import CoreGraphics
import CoreImage
import Foundation
import Metal
import MetalKit

/// Errors that can occur during texture comparison operations.
enum TextureComparisonError: Error {
    case noMetalDevice
    case failedToCreateCommandQueue
    case failedToLoadLibrary
    case functionNotFound
    /// Failed to create or load texture from image.
    case failedToCreateTexture
    case failedToCreateBuffer
    case failedToCreateCommandBuffer
    /// Textures must have identical dimensions to compare.
    case dimensionMismatch
    /// Metal is not supported on this device.
    case metalNotSupported
    /// Images have different color spaces and cannot be compared.
    case colorSpaceMismatch(lhs: CGColorSpace, rhs: CGColorSpace)
}

final class TextureCompare: Sendable {
    static let shared = TextureCompare()

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let psnrPipelineState: MTLComputePipelineState

    /// Calculate PSNR on CPU (for validation/comparison)
    /// - Parameters:
    ///   - textureA: First texture to compare
    ///   - textureB: Second texture to compare
    func calculatePSNRCPU(_ textureA: MTLTexture, _ textureB: MTLTexture) -> Double {
        let width = textureA.width
        let height = textureA.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel

        var pixelsA = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        var pixelsB = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        textureA.getBytes(&pixelsA, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        textureB.getBytes(&pixelsB, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)

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

    private init() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        self.device = device

        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("Failed to create Metal command queue")
        }
        self.commandQueue = commandQueue

        let library: MTLLibrary
        if let defaultLibrary = device.makeDefaultLibrary() {
            library = defaultLibrary
        } else if let bundleLibrary = try? device.makeDefaultLibrary(bundle: Bundle.module) {
            library = bundleLibrary
        } else if let shaderURL = Bundle.module.url(forResource: "TextureComparison", withExtension: "metal"),
                  let shaderSource = try? String(contentsOf: shaderURL),
                  let sourceLibrary = try? device.makeLibrary(source: shaderSource, options: nil) {
            library = sourceLibrary
        } else {
            fatalError("Failed to load Metal shader library")
        }

        guard let psnrFunction = library.makeFunction(name: "calculateSquaredDifferences") else {
            fatalError("Failed to find Metal function 'calculateSquaredDifferences'")
        }

        guard let pipelineState = try? device.makeComputePipelineState(function: psnrFunction) else {
            fatalError("Failed to create Metal compute pipeline state")
        }
        self.psnrPipelineState = pipelineState
    }

    func calculatePSNR(_ textureA: MTLTexture, _ textureB: MTLTexture) throws -> Double {
        let width = textureA.width
        let height = textureA.height
        let pixelCount = width * height

        let bufferLength = pixelCount * MemoryLayout<Float>.stride
        guard let squaredDiffBuffer = device.makeBuffer(
            length: bufferLength,
            options: .storageModeShared
        ) else {
            throw TextureComparisonError.failedToCreateBuffer
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw TextureComparisonError.failedToCreateCommandBuffer
        }

        encoder.setComputePipelineState(psnrPipelineState)
        encoder.setTexture(textureA, index: 0)
        encoder.setTexture(textureB, index: 1)
        encoder.setBuffer(squaredDiffBuffer, offset: 0, index: 0)

        let maxThreadsPerThreadgroup = psnrPipelineState.maxTotalThreadsPerThreadgroup
        let threadgroupWidth = Int(sqrt(Double(maxThreadsPerThreadgroup)))

        let threadsPerThreadgroup = MTLSize(
            width: threadgroupWidth,
            height: threadgroupWidth,
            depth: 1
        )

        let threadsPerGrid = MTLSize(
            width: width,
            height: height,
            depth: 1
        )

        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let squaredDiffPointer = squaredDiffBuffer.contents().assumingMemoryBound(to: Float.self)
        var sumSquaredDiff: Double = 0.0
        for i in 0..<pixelCount {
            sumSquaredDiff += Double(squaredDiffPointer[i])
        }

        let mse = sumSquaredDiff / Double(width * height * 4)

        if mse == 0.0 {
            // Return 120 dB for identical images (matches ImageMagick's behavior)
            return 120.0
        }

        let rmse = sqrt(mse)
        let psnr = 20.0 * log10(255.0 / rmse)

        // Cap PSNR at 120 dB to match ImageMagick's behavior
        return min(psnr, 120.0)
    }
}
