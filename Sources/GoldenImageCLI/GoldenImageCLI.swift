import ArgumentParser
import CoreGraphics
import Foundation
import GoldenImage
import ImageIO

@main
struct GoldenImageCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "golden-image-compare",
        abstract: "Calculate PSNR between two images using GPU acceleration"
    )

    @Argument(help: "Path to the first image")
    var image1: String

    @Argument(help: "Path to the second image")
    var image2: String

    func run() throws {
        guard let cgImage1 = loadImage(at: image1) else {
            throw ValidationError("Failed to load image at: \(image1)")
        }

        guard let cgImage2 = loadImage(at: image2) else {
            throw ValidationError("Failed to load image at: \(image2)")
        }

        let result = try ImageComparison().compare(cgImage1, cgImage2)

        if result.psnr >= 120.0 {
            print("PSNR: 120.00 dB (images are identical or nearly identical)")
        } else {
            print("PSNR: \(result.psnr)")
        }
    }

    func loadImage(at path: String) -> CGImage? {
        let url = URL(fileURLWithPath: path)
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
    }
}
