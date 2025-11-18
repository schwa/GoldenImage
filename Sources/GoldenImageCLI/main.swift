import CoreGraphics
import Foundation
import GoldenImage
import ImageIO
import Metal

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

        if psnr.isInfinite {
            print("PSNR: ∞ dB (images are identical)")
            exit(0)
        } else {
            print(String(format: "PSNR: %.2f dB", psnr))

            if psnr >= 40 {
                print("Quality: Excellent (nearly identical)")
                exit(0)
            } else if psnr >= 30 {
                print("Quality: Good (differences barely noticeable)")
                exit(0)
            } else if psnr >= 20 {
                print("Quality: Fair (differences visible)")
                exit(1)
            } else {
                print("Quality: Poor (significant differences)")
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

    Examples:
      \(programName) photo1.png photo2.png
      \(programName) /tmp/before.jpg /tmp/after.jpg

    Supported formats: PNG, JPEG, TIFF, and other formats supported by CGImageSource
    """)
}

func printError(_ message: String) {
    fputs("Error: \(message)\n", stderr)
}

main()
