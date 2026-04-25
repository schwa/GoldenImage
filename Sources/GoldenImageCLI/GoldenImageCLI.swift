import ArgumentParser
import CoreGraphics
import Foundation
import GoldenImage
import ImageIO

@main
internal struct GoldenImageCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "golden-image-compare",
        abstract: "Calculate PSNR between two images using GPU acceleration"
    )

    @Argument(help: "Path to the first image")
    var image1: String

    @Argument(help: "Path to the second image")
    var image2: String

    enum MatchMode: String, ExpressibleByArgument, CaseIterable {
        /// Standard PSNR must meet the threshold.
        case psnr
        /// Edge-aware (eroded) PSNR must meet the threshold. Ignores 1px AA halos along shape edges.
        case eroded
    }

    @Option(name: [.long, .customShort("m")], help: "Which PSNR variant to use when deciding a match: psnr (default) or eroded (edge-aware, ignores 1px AA halos).")
    var matchMode: MatchMode = .psnr

    @Option(name: .long, help: "PSNR threshold (in dB) for declaring a match. Defaults to 120 (identical or nearly identical).")
    var threshold: Double = 120.0

    @Option(name: .long, help: "Erosion kernel radius in pixels for edge-aware (eroded) comparison. 1 = 3×3 (suppresses 1px halos, default), 2 = 5×5 (suppresses 2px halos), etc.")
    var erosionRadius: Int = 1

    @Flag(name: [.long, .customShort("p")], help: "Open a window showing image A, image B, and the difference image. macOS only.")
    var preview: Bool = false

    @Option(name: .long, help: "Initial gain (multiplier) applied to the preview difference image to exaggerate subtle diffs. 1.0 = unmodified. Adjustable via the slider in the preview window.")
    var diffGain: Double = 1.0

    func run() throws {
        guard let cgImage1 = loadImage(at: image1) else {
            throw ValidationError("Failed to load image at: \(image1)")
        }

        guard let cgImage2 = loadImage(at: image2) else {
            throw ValidationError("Failed to load image at: \(image2)")
        }

        guard erosionRadius >= 1 else {
            throw ValidationError("--erosion-radius must be >= 1")
        }

        let comparison = ImageComparison(erosionRadius: erosionRadius)
        let result = try comparison.compare(cgImage1, cgImage2)

        if result.psnr >= 120.0 {
            print("PSNR: 120.00 dB (images are identical or nearly identical)")
        } else {
            print("PSNR: \(result.psnr)")
        }

        if let erodedPSNR = result.erodedPSNR {
            let kernel = 2 * erosionRadius + 1
            let suffix = "(edge-aware: \(kernel)×\(kernel) erosion, suppressing up to \(erosionRadius)px halos)"
            if erodedPSNR >= 120.0 {
                print("Eroded PSNR: 120.00 dB \(suffix)")
            } else {
                print("Eroded PSNR: \(erodedPSNR) \(suffix)")
            }
        }

        let psnrPasses = result.psnr >= threshold
        let erodedPasses = (result.erodedPSNR ?? 0) >= threshold

        let matched: Bool
        switch matchMode {
        case .psnr:
            matched = psnrPasses
        case .eroded:
            matched = erodedPasses
        }

        if matched {
            print("MATCH (threshold \(threshold) dB, mode \(matchMode.rawValue))")
        } else {
            print("NO MATCH (threshold \(threshold) dB, mode \(matchMode.rawValue))")
        }

        if preview {
            #if os(macOS)
            try MainActor.assumeIsolated {
                try PreviewWindow.show(
                    imageA: cgImage1,
                    imageB: cgImage2,
                    result: result,
                    titleA: URL(fileURLWithPath: image1).lastPathComponent,
                    titleB: URL(fileURLWithPath: image2).lastPathComponent,
                    erosionRadius: erosionRadius,
                    gain: diffGain
                )
            }
            #else
            print("--preview is only supported on macOS")
            #endif
        }

        if !matched {
            throw ExitCode.failure
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
