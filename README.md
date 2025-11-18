# GoldenImage

GPU-accelerated image comparison using PSNR (Peak Signal-to-Noise Ratio).

## Usage

```swift
import GoldenImage

let psnr = try calculatePSNR(lhs: image1, rhs: image2, lhsPath: "img1.png", rhsPath: "img2.png")
// Returns: ∞ dB (identical) or numeric value
```

## CLI

```bash
golden-image-compare image1.png image2.png
```

## Environment Variables

Auto-save comparisons by setting:

- `GOLDEN_IMAGE_OUTPUT=1` - Save to temp directory
- `GOLDEN_IMAGE_OUTPUT_PATH=/path` - Custom output directory
- `GOLDEN_IMAGE_OUTPUT_REVEAL=1` - Open in Finder (macOS)
- `GOLDEN_IMAGE_LOGGING=1` - Enable logging

### Output

Creates timestamped subdirectory with:
- Both images as PNG
- `comparison.txt` with PSNR and metadata

## PSNR Interpretation

- `∞ dB` - Identical images
- `> 40 dB` - Excellent (nearly identical)
- `30-40 dB` - Good (differences barely noticeable)
- `20-30 dB` - Fair (differences visible)
- `< 20 dB` - Poor (significant differences)

## License

MIT
