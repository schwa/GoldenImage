# GoldenImage

GPU-accelerated image comparison for Swift tests using Metal compute shaders.

## Features

- Fast PSNR (Peak Signal-to-Noise Ratio) calculation using Metal
- Compare images loaded as CGImage, CIImage, or MTLTexture
- Automatic color space normalization to sRGB
- macOS 13+

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/GoldenImage.git", from: "1.0.0")
]
```

## Usage

```swift
import GoldenImage
import Metal

let device = MTLCreateSystemDefaultDevice()!
let texture1 = try makeTexture(from: cgImage1, device: device)
let texture2 = try makeTexture(from: cgImage2, device: device)

let psnr = try calculatePSNR(lhs: texture1, rhs: texture2)

if psnr.isInfinite {
    print("Images are identical")
} else if psnr >= 40 {
    print("Excellent quality (nearly identical)")
} else if psnr >= 30 {
    print("Good quality")
} else {
    print("Images differ significantly")
}
```

## CLI Tool

Compare images from the command line:

```bash
swift run golden-image-compare image1.png image2.png
```

## PSNR Interpretation

- `∞ dB` - Identical images
- `> 40 dB` - Excellent (nearly identical)
- `30-40 dB` - Good (differences barely noticeable)
- `20-30 dB` - Fair (differences visible)
- `< 20 dB` - Poor (significant differences)

## License

MIT
