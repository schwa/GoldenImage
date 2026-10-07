# ISSUES.md

---

## 1: HDR comparison

+++
status: closed
priority: medium
kind: none
created: 2025-11-18T00:00:00Z
updated: 2026-04-24T20:20:34Z
closed: 2026-04-24T20:20:34Z
+++

---

## 2: Replace disabled ImageCompareTests with tests that don't depend on ImageMagick

+++
status: closed
priority: medium
kind: task
created: 2026-03-06T00:00:00Z
updated: 2026-04-24T20:23:32Z
closed: 2026-04-24T20:23:32Z
+++

14 tests in ImageCompareTests.swift are disabled because ImageMagick doesn't support EXR. These tests compare CPU/GPU PSNR results against ImageMagick as a reference. Need to either: remove the ImageMagick dependency from these tests (just test CPU vs GPU), or convert test images to a format ImageMagick supports (e.g. PNG) before comparing.

---

## 3: Edge-aware PSNR that ignores 1px AA halos

+++
status: closed
priority: medium
kind: feature
created: 2026-04-24T19:42:18Z
updated: 2026-04-24T20:03:44Z
closed: 2026-04-24T20:03:44Z
+++

Add a PSNR variant that excludes thin single-pixel differences (such as anti-aliasing halos along shape edges) from the error sum, so genuine interior mismatches aren't drowned out by unavoidable rasterizer edge differences.

## Motivation

When comparing two rasterized versions of the same vector artwork (e.g. SwiftUI Canvas vs a custom Metal renderer), the shapes are typically pixel-accurate in their interiors but differ by ~1 pixel of anti-aliasing along edges. This edge noise pulls PSNR down into the 30s even when the images are visually identical, making PSNR a poor signal for detecting real regressions.

A visual 'cleaned diff' using `CIMorphologyMinimum` (radius 1) on the diff image already confirms that eroding the per-pixel error removes the halo and leaves only meaningful differences.

## Proposal

Add an `erodedPSNR` (name TBD) computation that mirrors the visual erosion:

1. Compute the per-pixel squared-error map between A and B.
2. Apply a morphological erosion (minimum filter, radius 1) to that error map — equivalently, zero out any error pixel that has a zero-error neighbor.
3. Average the eroded error map and convert to dB as usual.

This is mathematically consistent with the 'cleaned diff' view: thin bright error pixels adjacent to matching pixels are discarded; solid error regions survive.

## API sketch

Extend `ImageComparison` with a second result field, e.g.:

```swift
public struct ComparisonResult {
    public let psnr: Double
    public let erodedPSNR: Double  // new
    // ...
}
```

Or provide an option on `compare` to select the mode.

## Notes

- Downsample-then-PSNR (2x box) was considered but is less consistent with the eroded-diff visualization and less selective.
- Erosion is asymmetric (only affects bright-on-dark), which matches how the per-pixel squared-error map is structured.
- Context: discovered while tuning the VectorDemo app in the Vector project, which displays A / B / Diff / PSNR per shape.

---

## 4: Generate diff image between two images

+++
status: closed
priority: medium
kind: feature
created: 2026-04-24T19:56:07Z
updated: 2026-04-24T20:13:21Z
closed: 2026-04-24T20:13:21Z
+++

Add a way to generate a visualization image showing the diff between two images.

---

## 5: GPU (MTLTexture) path feature parity with CPU

+++
status: new
priority: medium
kind: enhancement
created: 2026-04-24T20:24:31Z
+++

The GPU comparison path (via TextureCompare, used by the MTLTexture overload of ImageComparison.compare) only implements a subset of what the CPU path provides. Clients using the default CGImage/URL/CIImage/Image overloads are unaffected (those all route to CPU), but callers passing MTLTexture directly get weaker functionality.

Gaps to close:

1. **Eroded PSNR.** CPU path returns result.erodedPSNR; GPU path leaves it nil. Either port the 3x3 erosion to a Metal kernel operating on the per-pixel squared-error buffer, or read the buffer back and erode on the CPU.

2. **HDR / float textures.** The Metal shader (calculateSquaredDifferences) is hardcoded for 8-bit texture sampling and uses peak=255 in the PSNR formula. For rgba16Float / rgba32Float textures it should use peak=1.0. Needs either a separate HDR kernel or a generic one with a peak uniform.

3. **Difference image generation.** CPU has differenceImage(_:_:) and erodedDifferenceImage(_:_:); no MTLTexture equivalent exists.

4. **Color-space mismatch validation.** CPUCompare.compareDetailed throws colorSpaceMismatch when the two inputs disagree; the MTLTexture path only checks dimensions. MTLTextures don't carry CGColorSpace directly but we could at least check pixelFormat equivalence and document the expectation.

Current test coverage asserts CPU == GPU within 1 dB for standard PSNR on SDR images, which is the only overlap. Closing any of these would let us extend that oracle check further.

---

## 6: compare and differenceImage silently return wrong results when input color spaces don't match

+++
status: closed
priority: medium
kind: bug
created: 2026-04-25T21:38:34Z
updated: 2026-04-25T21:49:31Z
closed: 2026-04-25T21:49:31Z
+++

Both `ImageComparison.compare(_:_:)` and `differenceImage(_:_:)` walk pixel bytes assuming the two CGImages share a color space, but neither validates this. Feeding mismatched images (e.g. linear-sRGB vs sRGB) returns plausible-looking garbage:

- PSNR comes back low/wrong (bytes interpreted in the wrong gamma)
- Diff image can come back black/empty even when the images visibly differ

Repro: render one image into a CGContext with `CGColorSpace.linearSRGB` (16bpc), another into a normal sRGB texture, pass both to `compare` / `differenceImage`. PSNR will be low, diff will be near-black.

Suggested fix (one of):
1. `precondition(lhs.colorSpace == rhs.colorSpace)` (or at least same name/model).
2. Auto-convert one to match the other (probably via CGContext re-draw into a canonical sRGB-8 context internally) before computing.

Today users have to remember to manually re-encode both images into the same color space before calling these APIs, and forgetting silently produces wrong numbers.

---

## 7: Build warns 'missing creator for mutated node' for the resource bundle

+++
status: closed
priority: low
kind: bug
labels: effort:s
created: 2026-10-06T18:29:09Z
updated: 2026-10-07T17:24:42Z
closed: 2026-10-07T17:24:42Z
+++

Building a package that depends on GoldenImage (seen in MetalSprocketsGLTF with xcb test, Xcode 27.0 build system, macOS) prints:

warning: missing creator for mutated node: ('<package>/.build/out/Products/Debug/GoldenImage_GoldenImage.bundle/Contents/MacOS')

It is the only build warning left in MetalSprocketsGLTF. The bundle comes from the GoldenImage target's resources (.process("TextureComparison.metal")). Cause not verified: my guess is the processed Metal shader (a metallib in the resource bundle) makes the build system create Contents/MacOS in a resources-only bundle without a task that declares it. Possible fixes to try: compile the shader from source at runtime (makeLibrary(source:)) or with a different resource rule, and check whether the warning goes away.

---

## 8: Metal shader is compiled from source at runtime instead of shipping a precompiled metallib

+++
status: closed
priority: low
kind: task
created: 2026-10-07T17:24:58Z
updated: 2026-10-07T17:32:34Z
closed: 2026-10-07T17:32:34Z
+++

The fix for #7 switched TextureComparison.metal from .process to .copy in Package.swift. As a result the bundle ships the raw .metal source and the shader is compiled at runtime via makeLibrary(source:) on first use.

Downsides of runtime source compilation:
- Compilation cost on first use instead of build time.
- Shader errors surface at runtime rather than build time.
- Ships source instead of a compiled metallib.

Want to compile the shader at build time (ship a metallib) while still avoiding the 'missing creator for mutated node' warning from #7.

---
