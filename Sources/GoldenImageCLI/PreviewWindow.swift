#if os(macOS)
import AppKit
import CoreGraphics
import GoldenImage
import SwiftUI

/// Shows a SwiftUI window with image A, image B, and their diff.
/// Blocks until the window is closed.
@MainActor
internal enum PreviewWindow {
    static func show(imageA: CGImage, imageB: CGImage, result: ImageComparison.Result, titleA: String, titleB: String, erosionRadius: Int = 1, gain: Double = 1.0) throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let view = PreviewView(
            imageA: imageA,
            imageB: imageB,
            erosionRadius: erosionRadius,
            initialGain: gain,
            result: result,
            titleA: titleA,
            titleB: titleB
        )

        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "golden-image-compare"
        window.setContentSize(NSSize(width: 960, height: 420))
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)

        // Quit the app loop when the window closes.
        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                NSApplication.shared.stop(nil)
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        app.activate(ignoringOtherApps: true)
        app.run()
    }
}

private struct PreviewView: View {
    let imageA: CGImage
    let imageB: CGImage
    let erosionRadius: Int
    let result: ImageComparison.Result
    let titleA: String
    let titleB: String

    @State private var showEroded = false
    @State private var gain: Double

    init(imageA: CGImage, imageB: CGImage, erosionRadius: Int, initialGain: Double, result: ImageComparison.Result, titleA: String, titleB: String) {
        self.imageA = imageA
        self.imageB = imageB
        self.erosionRadius = erosionRadius
        self.result = result
        self.titleA = titleA
        self.titleB = titleB
        self._gain = State(initialValue: initialGain)
    }

    private var diffImage: CGImage? {
        let comparison = ImageComparison(erosionRadius: erosionRadius)
        if showEroded {
            return try? comparison.erodedDifferenceImage(imageA, imageB, gain: gain)
        }
        return try? comparison.differenceImage(imageA, imageB, gain: gain)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ImagePane(cgImage: imageA, title: titleA)
                ImagePane(cgImage: imageB, title: titleB)
                if let diff = diffImage {
                    ImagePane(
                        cgImage: diff,
                        title: showEroded ? "Difference (eroded)" : "Difference"
                    )
                }
            }
            .padding(8)

            Divider()

            HStack(spacing: 24) {
                PSNRLabel(prefix: "PSNR", value: result.psnr)
                if let eroded = result.erodedPSNR {
                    PSNRLabel(prefix: "Eroded PSNR", value: eroded)
                }
                Spacer()
                HStack(spacing: 6) {
                    Text(String(format: "Gain %.1f\u{00d7}", gain))
                        .frame(width: 80, alignment: .leading)
                    Slider(value: $gain, in: 1.0...256.0)
                        .frame(width: 160)
                }
                Toggle("Eroded diff", isOn: $showEroded)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .font(.system(.body, design: .monospaced))
            .padding(8)
        }
    }
}

private struct ImagePane: View {
    let cgImage: CGImage
    let title: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            Image(cgImage, scale: 1, label: Text(title))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .background(Color(white: 0.15))
                .border(Color.gray.opacity(0.4))
        }
    }
}

private struct PSNRLabel: View {
    let prefix: String
    let value: Double

    var body: some View {
        if value >= 120.0 {
            Text("\(prefix): 120.00 dB")
        } else {
            Text(String(format: "\(prefix): %.2f dB", value))
        }
    }
}
#endif
