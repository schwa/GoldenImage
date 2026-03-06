## 1: HDR comparison
status: new
priority: medium
kind: none
created: 2025-11-18


---

## 2: Replace disabled ImageCompareTests with tests that don't depend on ImageMagick
status: new
priority: medium
kind: task
created: 2026-03-06

14 tests in ImageCompareTests.swift are disabled because ImageMagick doesn't support EXR. These tests compare CPU/GPU PSNR results against ImageMagick as a reference. Need to either: remove the ImageMagick dependency from these tests (just test CPU vs GPU), or convert test images to a format ImageMagick supports (e.g. PNG) before comparing.

---

