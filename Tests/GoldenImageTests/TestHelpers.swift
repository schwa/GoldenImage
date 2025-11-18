import CoreGraphics
import CoreImage
import Foundation
@testable import GoldenImage
import Metal
import Testing

func createSolidColorCIImage(width: Int, height: Int, color: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)) -> CIImage {
    let ciColor = CIColor(red: color.r, green: color.g, blue: color.b, alpha: color.a)
    return CIImage(color: ciColor).cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
}

func createGradientCIImage(width: Int, height: Int) -> CIImage {
    let gradient = CIFilter(name: "CILinearGradient")!
    gradient.setValue(CIVector(x: 0, y: 0), forKey: "inputPoint0")
    gradient.setValue(CIVector(x: CGFloat(width), y: CGFloat(height)), forKey: "inputPoint1")
    gradient.setValue(CIColor(red: 1, green: 0, blue: 0, alpha: 1), forKey: "inputColor0")
    gradient.setValue(CIColor(red: 0, green: 0, blue: 1, alpha: 1), forKey: "inputColor1")
    return gradient.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
}

func createSolidColorTexture(width: Int, height: Int, color: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)) throws -> MTLTexture {
    let ciImage = createSolidColorCIImage(width: width, height: height, color: color)
    return try makeTexture(from: ciImage, device: TextureCompare.shared.device)
}

func createGradientTexture(width: Int, height: Int) throws -> MTLTexture {
    let ciImage = createGradientCIImage(width: width, height: height)
    return try makeTexture(from: ciImage, device: TextureCompare.shared.device)
}

func createSolidColorCGImage(width: Int, height: Int, color: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)) throws -> CGImage {
    let ciImage = createSolidColorCIImage(width: width, height: height, color: color)
    let context = CIContext()
    guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
        throw TextureComparisonError.failedToCreateTexture
    }
    return cgImage
}

func createCGImage(width: Int, height: Int, color: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat), colorSpace: CGColorSpace) throws -> CGImage {
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw TextureComparisonError.failedToCreateTexture
    }

    context.setFillColor(red: color.r, green: color.g, blue: color.b, alpha: color.a)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    guard let image = context.makeImage() else {
        throw TextureComparisonError.failedToCreateTexture
    }

    return image
}

func loadFixture(_ name: String) throws -> CIImage {
    guard let fixtureURL = Bundle.module.url(forResource: "Fixtures/\(name.replacingOccurrences(of: ".png", with: ""))", withExtension: "png") else {
        throw TestError.fixtureNotFound(name)
    }

    guard let ciImage = CIImage(contentsOf: fixtureURL) else {
        throw TestError.fixtureNotFound(name)
    }

    return ciImage
}

func cpuCompare(_ texture1: MTLTexture, _ texture2: MTLTexture) -> Bool {
    guard texture1.width == texture2.width, texture1.height == texture2.height else {
        return false
    }

    let width = texture1.width
    let height = texture1.height
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel

    var pixels1 = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
    var pixels2 = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

    texture1.getBytes(&pixels1, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
    texture2.getBytes(&pixels2, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)

    let epsilon: Int = 0

    for i in 0..<pixels1.count {
        let diff = abs(Int(pixels1[i]) - Int(pixels2[i]))
        if diff > epsilon {
            return false
        }
    }

    return true
}

func imagesAreIdentical(_ lhs: CGImage, _ rhs: CGImage) throws -> Bool {
    let device = TextureCompare.shared.device
    let textureA = try makeTexture(from: lhs, device: device)
    let textureB = try makeTexture(from: rhs, device: device)
    let psnr = try calculatePSNR(lhs: textureA, rhs: textureB)
    return psnr.isInfinite
}

func imagesAreIdentical(_ lhs: CIImage, _ rhs: CIImage) throws -> Bool {
    let device = TextureCompare.shared.device
    let textureA = try makeTexture(from: lhs, device: device)
    let textureB = try makeTexture(from: rhs, device: device)
    let psnr = try calculatePSNR(lhs: textureA, rhs: textureB)
    return psnr.isInfinite
}

func imagesAreIdentical(_ lhs: MTLTexture, _ rhs: MTLTexture) throws -> Bool {
    let psnr = try calculatePSNR(lhs: lhs, rhs: rhs)
    return psnr.isInfinite
}

func imagesAreDifferent(_ lhs: CGImage, _ rhs: CGImage) throws -> Bool {
    let device = TextureCompare.shared.device
    let textureA = try makeTexture(from: lhs, device: device)
    let textureB = try makeTexture(from: rhs, device: device)
    let psnr = try calculatePSNR(lhs: textureA, rhs: textureB)
    return !psnr.isInfinite
}

func imagesAreDifferent(_ lhs: CIImage, _ rhs: CIImage) throws -> Bool {
    let device = TextureCompare.shared.device
    let textureA = try makeTexture(from: lhs, device: device)
    let textureB = try makeTexture(from: rhs, device: device)
    let psnr = try calculatePSNR(lhs: textureA, rhs: textureB)
    return !psnr.isInfinite
}

func imagesAreDifferent(_ lhs: MTLTexture, _ rhs: MTLTexture) throws -> Bool {
    let psnr = try calculatePSNR(lhs: lhs, rhs: rhs)
    return !psnr.isInfinite
}

enum TestError: Error {
    case fixtureNotFound(String)
}
