# SideStore installation

## Current Orivyn preview

Add this separate source in SideStore → Sources → +:

https://raw.githubusercontent.com/R347H4CK3R/Orivyn-Distribution/main/source.json

The public [distribution-only repository](https://github.com/R347H4CK3R/Orivyn-Distribution) contains only the catalog, icon, install notes and unsigned IPA. The Orivyn source repository remains private. Jarvis Preview is a different source and was not modified.

### Verified build 4 distribution package

- Version **0.1.0**, build **4**, display name **Orivyn**, preserved bundle identifier `app.jarvisevo.ios`, ARM64, iOS **26.0+**.
- [Unsigned distribution IPA](https://raw.githubusercontent.com/R347H4CK3R/Orivyn-Distribution/main/Orivyn-0.1.0-build4-distribution-unsigned.ipa).
- Size **4,192,466 bytes**, SHA-256 `196091d0989f39a01787491efcfb7d1461bbca3a2f9d26f4d82b5bc7fa12ee7d`.
- All four public assets were independently downloaded without authentication and compared byte-for-byte after publication.
- This package adds the missing bundled llama.cpp MIT notice to the original verified unsigned build. Every original archive entry, including executable, framework, assets and Info.plist, is byte-identical. The original IPA is preserved separately: 4,192,549 bytes, SHA-256 `2e6084156b59d7cb0451a0bffc28cd3542264cca8416c4f508bb39ea2154be2c`.
- [Native build and QA evidence](ORIVYN_RECONSTRUCTION_QA.md): 62 Python checks, 288 native tests and 27 UI tests passed. App source `791dc4755a0ab1039d3fd628a9480d1d4419d182` includes the real default-model download, local answer and relaunch flow.

This is a **development preview**, not a fully device-accepted release. No physical-device installation or refresh has been verified. A catalog schema check and downloadable IPA do not prove SideStore installation works on a particular account/device.

## Installation procedure to validate on hardware

1. Follow current [official SideStore instructions](https://sidestore.io/) to configure signing and pairing. Keep Apple credentials and pairing files private.
2. Add the source above and install Orivyn, or download the IPA and import it into SideStore. The package is intentionally unsigned; SideStore must sign it for your Apple account/device.
3. Respect SideStore's current free signing, app-ID and refresh limits. No paid billing or Apple enrollment is enabled by this project.
4. Open Orivyn on an iOS 26+ iPhone. In Models, start with the approximately **491 MB** Qwen2.5 0.5B model on Wi-Fi. Nine official free download options are available, but larger models need more RAM/storage. Weights are not bundled in the IPA.
5. Send a short prompt and confirm a completed response. Relaunch and confirm the conversation and model selection persist.
6. Disable connectivity and repeat a local prompt. Test microphone/speech permissions, playback, stop/retry and SideStore refresh separately. Record device/OS, result and exact errors, never credentials.

The target is iPhone 16 Plus and iOS 26+. A simulator pass and valid ARM64 package do not verify memory/thermal behavior, hardware voice or LiveContainer compatibility. Build 4 has no cross-app incoming-text staging, local reminders or external account integrations; work on a later candidate does not change this published package.
