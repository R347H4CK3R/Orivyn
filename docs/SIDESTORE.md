# SideStore installation

## Current development candidate

A structurally verified **unsigned development candidate 2** is available. No GitHub release or catalog entry has been published. SideStore installation and refresh have not yet been tested on a physical device.

- Version **0.1.0**, build **2**, bundle identifier `app.jarvisevo.ios`, ARM64, iOS **26.0+**.
- CI artifact: `Jarvis-EVO-0.1.0-build2-unsigned.ipa`.
- Candidate attachment name: `Jarvis-EVO-0.1.0-build2-development-candidate-unsigned.ipa`.
- Both names refer to the same **2,457,684-byte** package.
- SHA-256: `6b2cf99647adb9862a1d32e4664dbf6a244233a1ebde4d0ffd9e0bbe991f8ff5`.
- Tested source: `1be1c99cb6ca1c68b5425a6cdfb0240963768b16`; [build and QA evidence](QA.md).

Use only this candidate's verified artifact when supplied as an attachment or obtained from the [recorded CI run](https://codemagic.io/app/6af4edea52f6da2271c62b79/build/6af507f3b54d2e261c61f4b7). Access to private CI artifacts may require the repository owner's account. Do not rename a source ZIP or download an unrelated Jarvis package as a substitute.

## Installation procedure to validate on hardware

1. Save the IPA and verify its file size and SHA-256 before importing it. On macOS, use `shasum -a 256 <filename>.ipa`; on Linux, use `sha256sum <filename>.ipa`.
2. Install and configure SideStore using the current [official instructions](https://sidestore.io/).
3. Import the IPA into SideStore and let SideStore sign it for your Apple account/device. The package is intentionally unsigned and cannot be installed directly.
4. Follow SideStore's current pairing, refresh and account limits. No Apple credentials belong in this repository or diagnostic reports.
5. Launch Jarvis-EVO on an iOS 26+ iPhone. Open Models, download the roughly **491 MB** Qwen model on Wi-Fi or import a compatible GGUF, and select it. Weights are not bundled in the IPA.
6. Send a short prompt and confirm a completed response. Relaunch and confirm the conversation and model selection persist.
7. Disable connectivity and repeat a local prompt. Test voice permissions/playback, stop/retry and refresh separately. Record device/OS, result and any exact error.

The target is iPhone 16 Plus and iOS 26+. Free Apple signing and SideStore provisioning limits can change. A simulator pass and valid ARM64 package do not verify installation, device offline behavior, hardware voice or LiveContainer compatibility. Treat this candidate as evaluation software until those gates pass.
