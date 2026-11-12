# Native Photos test fixture

OCR-card.png is an original, generated 1200 × 800 RGB text card, produced locally with Pillow and DejaVu Sans on 2026-11-12. It contains no personal data, EXIF, GPS, model output, or app UI. It is controlled image input, not screenshot evidence or an OCR stub.

SHA256: `956efa39a8e8f19c8c6d7c444cbb3b4443959fae6ceb71c785ced5df15282f4d`

Before native tests, scripts/run_native_tests.sh verifies this hash and seeds the card with `xcrun simctl addmedia` into the exact booted simulator in the xcodebuild destination. It does not access a user's Photos library. The UI test selects the card through the native Photos picker, waits for real ImageIO/Vision import, previews the real sanitized JPEG, verifies recognized text contains JARVIS 42, and checks sharing warnings/removal. No inference claim follows from this controlled input.

This directory belongs only to the UI test target, not JarvisEVO.app. Actual downloaded-model generation is covered independently by the existing real-model tests.
