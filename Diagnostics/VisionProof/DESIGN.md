# Native vision feasibility harness (not a product)

Parent-selected design: use the existing exact C ABI and one newly generated
llama.xcframework containing mtmd. No second runtime, Swift Package fallback,
main-app changes, automatic downloads, runtime services or bundled weights.
Alternative of CLI/subprocess vision is incompatible with iOS; a separate mtmd
runtime duplicates ownership. Neither is used.

1. Write XCTest boundary/ownership/real-image acceptance before source.
2. Copy the existing audited bridge verbatim; record SHA and upstream revision.
3. Decode owned encoded bytes via ImageIO: <=10MiB, exactly one frame, metadata
   <=40MP and <=16384 per dimension. Orientation-aware thumbnail <=512, sRGB
   white-composited RGBA then tightly packed RGB. No full-image decode fallback.
4. Single-use Swift worker owns one C session. Reserve work before dispatch;
   cancel latches before entry, no new entry after close. Cancel is independent
   of worker queue. Close cancels and waits for synchronous run before destroy.
   Results preserve status/report/actual UTF-8 bytes; canceled output not saved.
5. Tests use generated PNG pixels and orientation-tagged images, never expected
   answers substituted into model output. Optional real-model gate must be
   explicitly required by parent, verify both weights before native loading and
   attach actual model output/report. Native resource counters only count handles.
6. Parent supplies Frameworks/llama.xcframework after bounded build/symbol checks.
   This harness never builds it or starts CI. Native tests are authored/unrun here.

Limits: no physical iPhone evidence, jetsam budget, general vision quality, HEIC
fixture claim, production heavy-work admission integration, or release readiness.
