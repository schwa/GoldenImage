import CoreGraphics
import Foundation
import GoldenImage
import ImageIO
import Metal
import OSLog
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

let logger: Logger? = {
    if ProcessInfo.processInfo.environment["GOLDEN_IMAGE_LOGGING"] != nil {
        return Logger(subsystem: "com.goldenimage.cli", category: "comparison")
    }
    return nil
}()

func main() {
    let args = CommandLine.arguments

    guard args.count == 3 else {
        printUsage()
        exit(1)
    }

    let imagePath1 = args[1]
    let imagePath2 = args[2]

    guard let image1 = loadImage(at: imagePath1) else {
        printError("Failed to load image at: \(imagePath1)")
        exit(1)
    }

    guard let image2 = loadImage(at: imagePath2) else {
        printError("Failed to load image at: \(imagePath2)")
        exit(1)
    }

    do {
        guard let device = MTLCreateSystemDefaultDevice() else {
            printError("Metal is not supported on this device")
            exit(2)
        }

        let texture1 = try makeTexture(from: image1, device: device)
        let texture2 = try makeTexture(from: image2, device: device)

        let psnr = try calculatePSNR(lhs: texture1, rhs: texture2)

        // Save output images to temp directory if environment variable is set
        if let outputDir = ProcessInfo.processInfo.environment["GOLDEN_IMAGE_OUTPUT_DIR"] {
            try saveImagesToTempDirectory(image1: image1, image2: image2, imagePath1: imagePath1, imagePath2: imagePath2, outputDir: outputDir, psnr: psnr)
        } else if ProcessInfo.processInfo.environment["GOLDEN_IMAGE_SAVE"] != nil {
            // Use FileManager temp directory if no custom output directory specified
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("golden-image-comparisons").path
            try saveImagesToTempDirectory(image1: image1, image2: image2, imagePath1: imagePath1, imagePath2: imagePath2, outputDir: tempDir, psnr: psnr)
        }

        if psnr.isInfinite {
            logger?.info("PSNR: ∞ dB (images are identical)")
            exit(0)
        } else {
            logger?.info("PSNR: \(String(format: "%.2f", psnr)) dB")

            if psnr >= 40 {
                logger?.info("Quality: Excellent (nearly identical)")
                exit(0)
            } else if psnr >= 30 {
                logger?.info("Quality: Good (differences barely noticeable)")
                exit(0)
            } else if psnr >= 20 {
                logger?.info("Quality: Fair (differences visible)")
                exit(1)
            } else {
                logger?.info("Quality: Poor (significant differences)")
                exit(1)
            }
        }
    } catch {
        printError("PSNR calculation failed: \(error)")
        exit(2)
    }
}

func loadImage(at path: String) -> CGImage? {
    let url = URL(fileURLWithPath: path)

    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        return nil
    }

    return CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
}

func printUsage() {
    let programName = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent
    print("""
    Usage: \(programName) <image1> <image2>

    Calculate PSNR (Peak Signal-to-Noise Ratio) between two images using GPU acceleration.

    Arguments:
      image1    Path to the first image
      image2    Path to the second image

    Output:
      PSNR value in decibels (dB):
        ∞ dB       Images are identical
        > 40 dB    Excellent quality (nearly identical)
        30-40 dB   Good quality (differences barely noticeable)
        20-30 dB   Fair quality (differences visible)
        < 20 dB    Poor quality (significant differences)

    Exit codes:
      0    High quality (PSNR >= 30 dB) or identical images
      1    Low quality (PSNR < 30 dB) or invalid arguments
      2    Calculation error (Metal/GPU error)

    Environment Variables:
      GOLDEN_IMAGE_SAVE          If set, saves comparison images to FileManager's
                                 temporary directory under golden-image-comparisons/
      GOLDEN_IMAGE_OUTPUT_DIR    If set, saves comparison images to the specified
                                 directory instead of the default temp location
      GOLDEN_IMAGE_REVEAL        If set (macOS only), reveals the output directory
                                 in Finder after saving images
      GOLDEN_IMAGE_LOGGING       If set, enables os_log logging for diagnostics

    Examples:
      \(programName) photo1.png photo2.png
      \(programName) /tmp/before.jpg /tmp/after.jpg
      GOLDEN_IMAGE_SAVE=1 \(programName) img1.png img2.png
      GOLDEN_IMAGE_SAVE=1 GOLDEN_IMAGE_REVEAL=1 \(programName) a.png b.png
      GOLDEN_IMAGE_OUTPUT_DIR=~/comparisons \(programName) img1.png img2.png

    Supported formats: PNG, JPEG, TIFF, and other formats supported by CGImageSource
    """)
}

func printError(_ message: String) {
    fputs("Error: \(message)\n", stderr)
}

func saveImagesToTempDirectory(image1: CGImage, image2: CGImage, imagePath1: String, imagePath2: String, outputDir: String, psnr: Double) throws {
    let fileManager = FileManager.default

    // Create output directory if it doesn't exist
    let outputURL = URL(fileURLWithPath: outputDir)
    try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true, attributes: nil)

    // Generate filenames based on the original image names
    let name1 = URL(fileURLWithPath: imagePath1).deletingPathExtension().lastPathComponent
    let name2 = URL(fileURLWithPath: imagePath2).deletingPathExtension().lastPathComponent

    // Create timestamped subdirectory
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    let timestamp = dateFormatter.string(from: Date())

    let subdirName = "\(name1)_vs_\(name2)_\(timestamp)"
    let subdirURL = outputURL.appendingPathComponent(subdirName)
    try fileManager.createDirectory(at: subdirURL, withIntermediateDirectories: true, attributes: nil)

    // Save images
    let image1URL = subdirURL.appendingPathComponent("\(name1).png")
    let image2URL = subdirURL.appendingPathComponent("\(name2).png")

    try saveImage(image1, to: image1URL)
    try saveImage(image2, to: image2URL)

    // Save metadata
    let metadataURL = subdirURL.appendingPathComponent("comparison.txt")
    let psnrString = psnr.isInfinite ? "∞" : String(format: "%.2f", psnr)
    let metadata = """
    Image Comparison Results
    =======================
    Timestamp: \(timestamp)
    Image 1: \(imagePath1)
    Image 2: \(imagePath2)
    PSNR: \(psnrString) dB
    Dimensions: \(image1.width)×\(image1.height)
    """
    try metadata.write(to: metadataURL, atomically: true, encoding: .utf8)

    logger?.info("Images saved to: \(subdirURL.path)")

    // Reveal in Finder if environment variable is set (macOS only)
    #if os(macOS)
    if ProcessInfo.processInfo.environment["GOLDEN_IMAGE_REVEAL"] != nil {
        NSWorkspace.shared.selectFile(subdirURL.path, inFileViewerRootedAtPath: "")
        logger?.info("Revealed in Finder")
    }
    #endif
}

func saveImage(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "GoldenImageCLI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create image destination"])
    }

    CGImageDestinationAddImage(destination, image, nil)

    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "GoldenImageCLI", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to write image to \(url.path)"])
    }
}

main()
