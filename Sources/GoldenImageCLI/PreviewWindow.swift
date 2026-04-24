#if os(macOS)
import AppKit
import CoreGraphics
import GoldenImage
import SwiftUI

/// Shows a SwiftUI window with image A, image B, and their diff.
/// Blocks until the window is closed.
@MainActor
internal enum PreviewWindow {
    static func show(imageA: CGImage, imageB: CGImage, result: ImageComparison.Result, titleA: String, titleB: String, erosionRadius: Int = 1) throws {
        let comparison = ImageComparison(erosionRadius: erosionRadius)
        let diff = try comparison.differenceImage(imageA, imageB)
        let erodedDiff = try comparison.erodedDifferenceImage(imageA, imageB)

        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let view = PreviewView(
            imageA: imageA,
            imageB: imageB,
            diff: diff,
            erodedDiff: erodedDiff,
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
    let diff: CGImage
    let erodedDiff: CGImage
    let result: ImageComparison.Result
    let titleA: String
    let titleB: String

    @State private var showEroded = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ImagePane(cgImage: imageA, title: titleA)
                ImagePane(cgImage: imageB, title: titleB)
                ImagePane(
                    cgImage: showEroded ? erodedDiff : diff,
                    title: showEroded ? "Difference (eroded)" : "Difference"
                )
            }
            .padding(8)

            Divider()

            HStack(spacing: 24) {
                PSNRLabel(prefix: "PSNR", value: result.psnr)
                if let eroded = result.erodedPSNR {
                    PSNRLabel(prefix: "Eroded PSNR", value: eroded)
                }
                Spacer()
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
