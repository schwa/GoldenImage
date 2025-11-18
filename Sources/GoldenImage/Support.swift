import CoreGraphics
import CoreImage
import Foundation
import Metal
import MetalKit

/// Convert CGImage to Metal texture, normalizing to sRGB color space.
public func makeTexture(from image: CGImage, device: MTLDevice) throws -> MTLTexture {
    guard let srgbColorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
        throw TextureComparisonError.failedToCreateTexture
    }

    let normalizedImage: CGImage
    if let imageColorSpace = image.colorSpace, imageColorSpace != srgbColorSpace {
        guard let converted = image.copy(colorSpace: srgbColorSpace) else {
            throw TextureComparisonError.failedToCreateTexture
        }
        normalizedImage = converted
    } else {
        normalizedImage = image
    }

    let textureLoader = MTKTextureLoader(device: device)
    let options: [MTKTextureLoader.Option: Any] = [
        .textureUsage: MTLTextureUsage.shaderRead.rawValue,
        .SRGB: false
    ]

    do {
        return try textureLoader.newTexture(cgImage: normalizedImage, options: options)
    } catch {
        throw TextureComparisonError.failedToCreateTexture
    }
}

/// Convert CIImage to Metal texture, normalizing to sRGB color space.
public func makeTexture(from image: CIImage, device: MTLDevice) throws -> MTLTexture {
    guard let srgbColorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
        throw TextureComparisonError.failedToCreateTexture
    }

    let context = CIContext(mtlDevice: device, options: [.workingColorSpace: srgbColorSpace])

    let width = Int(image.extent.width)
    let height = Int(image.extent.height)

    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm,
        width: width,
        height: height,
        mipmapped: false
    )
    descriptor.usage = [.shaderRead, .shaderWrite]

    guard let texture = device.makeTexture(descriptor: descriptor) else {
        throw TextureComparisonError.failedToCreateTexture
    }

    guard let commandQueue = device.makeCommandQueue(),
          let commandBuffer = commandQueue.makeCommandBuffer() else {
        throw TextureComparisonError.failedToCreateCommandBuffer
    }

    context.render(image, to: texture, commandBuffer: commandBuffer, bounds: image.extent, colorSpace: srgbColorSpace)

    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()

    return texture
}
