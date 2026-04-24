# GoldenImage

Image comparison using PSNR (Peak Signal-to-Noise Ratio), with optional edge-aware
and HDR variants. CPU path by default; a Metal GPU path is available for
`MTLTexture` inputs.

## Usage

```swift
import GoldenImage

let result = try ImageComparison().compare(image1, image2)
print("PSNR: \(result.psnr) dB")
print("Match: \(result.isMatch)") // true if PSNR >= 120 dB (effectively identical)

if let erodedPSNR = result.erodedPSNR {
    print("Eroded PSNR: \(erodedPSNR) dB")  // edge-aware, ignores 1px AA halos
    print("Match (ignoring edges): \(result.isMatchIgnoringEdges)")
}
```

### Choosing your own threshold

`isMatch` and `isMatchIgnoringEdges` use a strict 120 dB threshold meaning
*"effectively identical"*. For many real comparisons that's too strict —
lossy compression, font hinting differences, or different rasterizers will
easily drop PSNR into the 40–60 dB range while still being visually
indistinguishable. Compare against your own threshold instead:

```swift
let result = try ImageComparison().compare(image1, image2)

// Common thresholds:
//   60 dB — nearly indistinguishable, tolerates encoder noise
//   40 dB — good visual match, tolerates JPEG / heavy resampling
//   30 dB — acceptable for thumbnails / previews
let threshold = 40.0
#expect(result.psnr >= threshold)
```

For the golden-image flow, pass your threshold to `GoldenImageComparison`:

```swift
let golden = GoldenImageComparison(
    imageDirectory: goldensDirectory,
    psnrThreshold: 40.0  // accept anything 40 dB or better
)
```

For the CLI use `--threshold`:

```bash
golden-image-compare --threshold 40 a.png b.png
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
erased. Treat `psnr` as the primary signal and `erodedPSNR` as a secondary
check answering *"does the difference survive edge erosion?"*.

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
`failureOutputDirectory` (or `FileManager.default.temporaryDirectory` +
`GoldenImages/` by default) and
`GoldenImageError.noGoldenImage(savedTo:)` is thrown — so you can inspect the
output and promote it to the golden directory manually.

### Use in a unit test (Swift Testing)

```swift
import GoldenImage
import Testing

@Test
func renderedShape_matchesGolden() throws {
    let rendered = MyRenderer().render(...)
    let golden = GoldenImageComparison(imageDirectory: goldensDirectory)
    #expect(try golden.image(image: rendered, matchesGoldenImageNamed: "circle"))
}
```

On the first run there's no golden yet, so the call throws
`GoldenImageError.noGoldenImage(savedTo:)` and writes the rendered image to
`savedTo`. Inspect it, copy it into `goldensDirectory`, and the next run
compares against it.
Subsequent runs compare against the saved golden.

## CLI

A `golden-image-compare` executable is included for ad-hoc PSNR comparisons
from the command line, including a macOS preview window. Run with `--help`
for flags and usage.

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

## Platforms

macOS 15+, iOS 18+. Swift 6.1. Preview window is macOS-only.

## License

MIT
