# GoldenImage

Image comparison using PSNR (Peak Signal-to-Noise Ratio), with optional edge-aware
and HDR variants. CPU path by default; a Metal GPU path is available for
`MTLTexture` inputs.

## Usage

```swift
import GoldenImage

let result = try ImageComparison().compare(image1, image2)
print("PSNR: \(result.psnr) dB")
print("Match: \(result.isMatch)") // true if PSNR >= 120 dB

if let erodedPSNR = result.erodedPSNR {
    print("Eroded PSNR: \(erodedPSNR) dB")  // edge-aware, ignores 1px AA halos
    print("Match (ignoring edges): \(result.isMatchIgnoringEdges)")
}
```

### Supported inputs

The `ImageComparison` type has overloads for:

- `CGImage` — Core Graphics images (CPU path)
- `CIImage` — Core Image (rendered to CGImage first, CPU path)
- `MTLTexture` — Metal textures (GPU path, SDR only; see *Feature matrix* below)
- `URL` — Loads the file, then uses the CPU path
- `SwiftUI.Image` — Rendered via `ImageRenderer`, CPU path

### Difference images

```swift
let diff        = try ImageComparison().differenceImage(image1, image2)
let erodedDiff  = try ImageComparison().erodedDifferenceImage(image1, image2)
```

`erodedDifferenceImage` applies a 3×3 morphological erosion so single-pixel
differences (such as anti-aliasing halos along shape edges) are suppressed.

### Edge-aware PSNR (`erodedPSNR`)

When comparing two rasterizations of the same artwork — for example a SwiftUI
Canvas render vs. a custom Metal renderer — the shapes are typically pixel-
accurate in their interiors but differ by roughly one pixel of anti-aliasing
along edges. This edge noise can pull PSNR into the 30s even when the images
are visually identical.

`erodedPSNR` computes PSNR after applying a 3×3 erosion to the per-pixel
squared-error map (any pixel with a zero-error neighbor is discarded). Solid
regions of error survive; single-pixel halos disappear.

**Caveat.** The kernel cannot distinguish a genuine single-pixel-wide feature
(a 1pt stroke, a hairline, an isolated pixel) from an AA halo — both are
erased. Empirically:

| Stroke width | PSNR vs. blank | Eroded PSNR | Δ |
|---|---|---|---|
| 1 pt | 23.6 dB | 120 dB | +96 dB ⚠️ vanishes |
| 2 pt | 20.6 dB | 25.8 dB | +5 dB |
| 3 pt | 18.9 dB | 21.5 dB | +3 dB |
| 6 pt | 15.8 dB | 16.9 dB | +1 dB |

Treat `psnr` as the primary signal and `erodedPSNR` as a secondary check
answering *"does the difference survive edge erosion?"*.

### HDR comparison

Float-component images, >8bpc images, and images in extended-range color
spaces are automatically routed to an HDR comparison path that uses a
`peak=1.0` reference (vs. `peak=255` for 8-bit SDR). Detection is based on
`CGImage.bitmapInfo`, `bitsPerComponent`, and the color space.

### Golden-image testing

```swift
let golden = GoldenImageComparison(
    imageDirectory: URL(fileURLWithPath: "Tests/GoldenImages"),
    options: .ignoreEdgeAAHalos,   // optional: accept edge-only differences
    psnrThreshold: 120.0
)
let matches = try golden.image(image: rendered, matchesGoldenImageNamed: "my_test")
```

If no golden image exists at that name, the input image is written to
`failureOutputDirectory` (or `$TMPDIR/GoldenImages/` by default) and
`GoldenImageError.noGoldenImage(savedTo:)` is thrown — so you can inspect the
output and promote it to the golden directory manually.

### Use in a unit test (Swift Testing)

```swift
import CoreGraphics
import GoldenImage
import Testing

@Suite struct MyRendererTests {
    /// Resolve a `Tests/<Suite>/Goldens/` directory next to this file.
    private var goldensDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Goldens")
    }

    @Test
    func renderedShape_matchesGolden() throws {
        let rendered: CGImage = MyRenderer().render(.circle, size: CGSize(width: 256, height: 256))

        let golden = GoldenImageComparison(
            imageDirectory: goldensDirectory,
            options: .ignoreEdgeAAHalos  // tolerate 1px AA differences along edges
        )

        do {
            #expect(try golden.image(image: rendered, matchesGoldenImageNamed: "circle"))
        } catch let GoldenImageError.noGoldenImage(savedTo) {
            // First run: no golden exists yet. The rendered image was written to
            // savedTo so you can inspect it and copy it into goldensDirectory to
            // promote it as the new reference.
            Issue.record("No golden image; review and promote: \(savedTo?.path ?? "<temp>")")
        }
    }

    /// Lower-level: assert directly on PSNR / erodedPSNR if you don't need the
    /// golden-image directory machinery.
    @Test
    func twoRenderers_agreeIgnoringAAEdges() throws {
        let canvas: CGImage = SwiftUIRenderer().render(...)
        let metal: CGImage  = MetalRenderer().render(...)

        let result = try ImageComparison().compare(canvas, metal)

        // Edge AA differences are expected; require the eroded score to match.
        #expect(result.isMatchIgnoringEdges,
                "PSNR: \(result.psnr) dB, eroded: \(result.erodedPSNR ?? .nan) dB")
    }
}
```

First run produces a `noGoldenImage` failure with the rendered output saved
to a temp location; copy it into `goldensDirectory` to lock in the reference.
Subsequent runs compare against the saved golden.

## CLI

```bash
golden-image-compare <image1> <image2> [options]
```

Options:

| Flag | Description |
|---|---|
| `-m, --match-mode <psnr\|eroded>` | Which PSNR variant decides the match. Default `psnr`. |
| `--threshold <dB>` | PSNR threshold for declaring a match. Default `120`. |
| `-p, --preview` | (macOS) Opens a SwiftUI window showing image A, image B, and the difference image, with a toggle to swap between the regular and eroded difference. |

Exits non-zero on NO MATCH.

Example:

```
$ golden-image-compare edge_aa_a.png edge_aa_b.png
PSNR: 38.21
Eroded PSNR: 120.00 dB (edge-aware: ignoring 1px AA halos)
NO MATCH (threshold 120.0 dB, mode psnr)

$ golden-image-compare -m eroded edge_aa_a.png edge_aa_b.png
PSNR: 38.21
Eroded PSNR: 120.00 dB (edge-aware: ignoring 1px AA halos)
MATCH (threshold 120.0 dB, mode eroded)
```

## Feature matrix

| Feature                   | CGImage / URL / CIImage / Image | MTLTexture |
|---------------------------|:-:|:-:|
| Standard PSNR             | ✅ | ✅ |
| Eroded PSNR               | ✅ | ❌ (returns `nil`) |
| HDR / float inputs        | ✅ | ❌ |
| Difference image          | ✅ | ❌ |
| Eroded difference image   | ✅ | ❌ |
| Color-space mismatch check| ✅ | ❌ |

The `MTLTexture` overload is an opt-in fast path for Metal-native callers.
All other overloads go through the fully-featured CPU implementation.

## PSNR interpretation

- `≥ 120 dB` — identical or nearly identical
- `> 40 dB` — excellent (differences barely noticeable)
- `30–40 dB` — good (minor differences)
- `20–30 dB` — fair (differences visible)
- `< 20 dB` — poor (significant differences)

## Platforms

macOS 15+, iOS 18+. Swift 6.1. Preview window is macOS-only.

## License

MIT
