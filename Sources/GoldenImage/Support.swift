import CoreGraphics
import CoreImage
import Foundation
import Metal
import MetalKit
import UniformTypeIdentifiers

/// Convert CGImage to Metal texture, normalizing to linear RGB color space.
///
/// Note: We manually extract pixels via CGContext instead of using MTKTextureLoader because
/// MTKTextureLoader unpremultiplies alpha for rendering workflows, but we need premultiplied
/// alpha to match the CPU comparison path and produce correct PSNR values.
func makeTexture(from image: CGImage, device: MTLDevice) throws -> MTLTexture {
    guard let linearColorSpace = CGColorSpace(name: CGColorSpace.linearSRGB) else {
        throw TextureComparisonError.failedToCreateTexture
    }

    let width = image.width
    let height = image.height
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    let totalBytes = width * height * bytesPerPixel

    let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
    var pixels = [UInt8](repeating: 0, count: totalBytes)

    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: linearColorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        throw TextureComparisonError.failedToCreateTexture
    }

    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm,
        width: width,
        height: height,
        mipmapped: false
    )
    descriptor.usage = [.shaderRead]

    guard let texture = device.makeTexture(descriptor: descriptor) else {
        throw TextureComparisonError.failedToCreateTexture
    }

    texture.replace(
        region: MTLRegionMake2D(0, 0, width, height),
        mipmapLevel: 0,
        withBytes: pixels,
        bytesPerRow: bytesPerRow
    )

    return texture
}

/// Convert CIImage to Metal texture, normalizing to linear RGB color space.
func makeTexture(from image: CIImage, device: MTLDevice) throws -> MTLTexture {
    guard let linearColorSpace = CGColorSpace(name: CGColorSpace.linearSRGB) else {
        throw TextureComparisonError.failedToCreateTexture
    }

    let context = CIContext(mtlDevice: device, options: [.workingColorSpace: linearColorSpace])

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

    context.render(image, to: texture, commandBuffer: commandBuffer, bounds: image.extent, colorSpace: linearColorSpace)

    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()

    return texture
}

extension FileManager {
    func url(ofDirectory directory: URL, named name: String, conformingTo: UTType) -> URL? {
        guard let contents = try? contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentTypeKey]) else {
            return nil
        }

        return contents.first { fileURL in
            let filename = fileURL.deletingPathExtension().lastPathComponent
            guard filename == name else {
                return false
            }

            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.contentTypeKey]),
                  let contentType = resourceValues.contentType else {
                return false
            }

            return contentType.conforms(to: conformingTo)
        }
    }
}


extension CGImage {

    func write(to url: URL, type: UTType? = nil, properties: [CFString: Any]? = nil) throws {
        let uti = type ?? UTType(filenameExtension: url.pathExtension) ?? .png
        guard let imageDestination = CGImageDestinationCreateWithURL(url as CFURL, uti.identifier as CFString, 1, nil) else {
            fatalError("Failed to create image destination")
        }
        CGImageDestinationAddImage(imageDestination, self, properties as CFDictionary?)
        guard CGImageDestinationFinalize(imageDestination) else {
            throw NSError(domain: "GoldenImage", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to write image to \(url.path)"])
        }
    }

    func writeEXR(to url: URL, compression: String = "ZIP") throws {

        assert(url.pathExtension.lowercased() == "exr", "URL must have .exr extension")
        guard let imageDestination = CGImageDestinationCreateWithURL(url as CFURL, UTType.exr.identifier as CFString, 1, nil) else {
            fatalError("Failed to create image destination")
        }
//        let exrOptions: [CFString: Any] = [
//            kCGImagePropertyOpenEXRCompression: compression// "ZIP" // or "PIZ", "RLE", etc.
//        ]
//        let options: [CFString: Any] = [
//            kCGImagePropertyOpenEXRDictionary: exrOptions
//        ]
//        CGImageDestinationAddImage(imageDestination, self, options as CFDictionary)
        CGImageDestinationAddImage(imageDestination, self, nil)
        guard CGImageDestinationFinalize(imageDestination) else {
            throw NSError(domain: "GoldenImage", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to write image to \(url.path)"])
        }
    }
}

import AppKit

extension URL {
    func reveal() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: self.path)
    }
}
