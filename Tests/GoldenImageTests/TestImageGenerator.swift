import Foundation
import SwiftUI
import UniformTypeIdentifiers
import ImageIO

#if canImport(AppKit)
import AppKit
#endif

/// Generates test images for the test suite
struct TestImageGenerator {

    /// The cache directory where test images are stored
    static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GoldenImageTests")
    }

    /// Generate an image from a SwiftUI view and save as EXR
    @MainActor
    static func generate<Content: View>(
        name: String,
        size: CGSize = CGSize(width: 256, height: 256),
        @ViewBuilder content: () -> Content
    ) throws {
        // Create cache directory if needed
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        let url = cacheDirectory.appendingPathComponent("\(name).exr")

        // Skip if already exists
        if FileManager.default.fileExists(atPath: url.path) {
            return
        }

        // Render to CGImage using ImageRenderer
        let renderer = ImageRenderer(content: content().frame(width: size.width, height: size.height))
        renderer.scale = 1.0

        guard let cgImage = renderer.cgImage else {
            throw TestImageError.failedToRender(name)
        }

        // Save as EXR
        try saveAsEXR(cgImage: cgImage, to: url)

        // Reveal in Finder if environment variable is set
        if ProcessInfo.processInfo.environment["GOLDEN_IMAGE_TEST_REVEAL"] != nil {
            #if os(macOS)
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: cacheDirectory.path)
            #endif
        }
    }

    /// Save a CGImage as an EXR file
    private static func saveAsEXR(cgImage: CGImage, to url: URL) throws {
        // Create image destination for EXR format
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            "com.ilm.openexr-image" as CFString,
            1,
            nil
        ) else {
            throw TestImageError.failedToCreateDestination(url.path)
        }

        // Add the image
        CGImageDestinationAddImage(destination, cgImage, nil)

        // Finalize the write
        guard CGImageDestinationFinalize(destination) else {
            throw TestImageError.failedToWriteImage(url.path)
        }
    }

    /// Get the URL for a test image
    static func imageURL(named name: String) -> URL {
        cacheDirectory.appendingPathComponent("\(name).exr")
    }
}

enum TestImageError: Error, CustomStringConvertible {
    case failedToRender(String)
    case failedToCreateDestination(String)
    case failedToWriteImage(String)

    var description: String {
        switch self {
        case .failedToRender(let name):
            return "Failed to render image: \(name)"
        case .failedToCreateDestination(let path):
            return "Failed to create image destination at: \(path)"
        case .failedToWriteImage(let path):
            return "Failed to write image to: \(path)"
        }
    }
}
