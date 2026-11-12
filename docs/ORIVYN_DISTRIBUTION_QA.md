# Orivyn public distribution verification

Verified November 12, 2026. The owner explicitly approved a separate **public distribution-only** repository for the verified unsigned IPA, icon, catalog and install notes, while preserving private application source and the separate Jarvis Preview source.

## Published result

- Repository: https://github.com/R347H4CK3R/Orivyn-Distribution
- Public repository numeric ID: `1455537927`.
- Publication commit: `069f1c7cbeea69c13833d0def5e38d04e2900a9c`.
- Catalog: https://raw.githubusercontent.com/R347H4CK3R/Orivyn-Distribution/main/source.json
- Exactly four files were published: `source.json`, `icon.png`, `README.md`, `Orivyn-0.1.0-build4-distribution-unsigned.ipa`. No source code, logs, credentials, model weights or personal conversations were uploaded.
- The existing application repository `R347H4CK3R/Orivyn`, numeric ID `1454512475`, was independently rechecked and remains **private**. No Jarvis repository or source was modified by this operation.

## Package provenance

The original verified build-4 IPA is preserved unchanged: 4,192,549 bytes, SHA-256 `2e6084156b59d7cb0451a0bffc28cd3542264cca8416c4f508bb39ea2154be2c`.

Before publication, inspection found that the llama.cpp MIT notice was present in source but missing from the app bundle. A clearly named distribution copy adds **only** `Payload/JarvisEVO.app/llama.cpp-LICENSE.txt`. Every original ZIP entry's decompressed contents were compared and are byte-identical, including executable, framework, Info.plist, assets and KaTeX resources. Container compression/metadata may differ, so this is not the original archive and has its own checksum. No app logic, version, identifier or signing state was changed.

- Distribution package: **4,192,466 bytes**.
- SHA-256: `196091d0989f39a01787491efcfb7d1461bbca3a2f9d26f4d82b5bc7fa12ee7d`.
- Bundled notice SHA-256: `94f29bbed6a22c35b992c5c6ebf0e7c92f13b836b90f36f461c9cf2f0f1d010d`, matching the official [llama.cpp b9049 license](https://github.com/ggml-org/llama.cpp/blob/b9049/LICENSE).
- Existing package verifier passed independently on both the prepared distribution copy and its public re-download: ARM64 physical iPhoneOS target, iOS 26.0 minimum, version 0.1.0 build 4, preserved `app.jarvisevo.ios`, no DEBUG fixture markers/test media/GGUF weights, exact KaTeX resources.

The [native build-4 evidence](ORIVYN_RECONSTRUCTION_QA.md) applies to the unchanged application payload. The license-only repack itself was verified structurally and byte-by-byte, not by rerunning the simulator suite on a new compilation.

## Public fetch checks

Anonymous HTTPS GET requests returned **200** for all four files. Each downloaded body matched its prepared file exactly:

| File | Bytes | SHA-256 |
|---|---:|---|
| `source.json` | 2,379 | `15c1d6d09e656dab8309a4cb381df047b12cc272364cbd0cab6fbd2dc1059276` |
| `icon.png` | 552,314 | `5d7bb862db12575a7c103936716585cc16369c0488f58febe8881f7dac4b3538` |
| `README.md` | 3,393 | `5d2f12e8f29645be81cef7166e2acf2d6ec1ca927bba202180afe38b46eb8573` |
| unsigned IPA | 4,192,466 | `196091d0989f39a01787491efcfb7d1461bbca3a2f9d26f4d82b5bc7fa12ee7d` |

The catalog validated against the official SideStore source-types schema. It uses a separate stable source identifier, correct app bundle/version/minimum-OS metadata, direct anonymous download URL, exact IPA byte count and actual permission descriptions. No marketplace ID, notarization field, paid tier or Patreon gate was added.

## Remaining acceptance

No connected iPhone/Mac was available. SideStore source ingestion, signing, installation, free-account refresh, actual hardware voice, offline operation, memory/thermal behavior and LiveContainer compatibility remain unverified. The public README and app description disclose these limits. The catalog is a development preview, not a promise that every app feature or device workflow is complete.
