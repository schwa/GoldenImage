# GoldenImage

GPU-accelerated image comparison using PSNR (Peak Signal-to-Noise Ratio).

## Usage

```swift
import GoldenImage

let comparison = ImageComparison()
let result = try comparison.compare(image1, image2)
print("PSNR: \(result.psnr) dB")
print("Match: \(result.isMatch)") // true if PSNR >= 120 dB
```

The `ImageComparison` type supports multiple image formats:
- `CGImage` - Core Graphics images
- `CIImage` - Core Image images
- `MTLTexture` - Metal textures (GPU-accelerated)
- `URL` - Load and compare images from file URLs
- `Image` - SwiftUI images (macOS only)

## CLI

```bash
golden-image-compare image1.png image2.png
```

Example output:
```
PSNR: 120.00 dB (images are identical or nearly identical)
```

## PSNR Interpretation

- `≥ 120 dB` - Identical or nearly identical images
- `> 40 dB` - Excellent (differences barely noticeable)
- `30-40 dB` - Good (minor differences)
- `20-30 dB` - Fair (differences visible)
- `< 20 dB` - Poor (significant differences)

## License

MIT
