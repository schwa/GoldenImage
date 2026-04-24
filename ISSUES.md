# ISSUES.md

---

## 1: HDR comparison

+++
status: new
priority: medium
kind: none
created: 2025-11-18T00:00:00Z
+++

---

## 2: Replace disabled ImageCompareTests with tests that don't depend on ImageMagick

+++
status: new
priority: medium
kind: task
created: 2026-03-06T00:00:00Z
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
