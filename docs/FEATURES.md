# Feature and compatibility matrix

Evidence below applies to application source `3628cf57c49a57d116140780d3973761e8a1c336`, tested by CI commit `db4d8714a110956f370c00fb8b4c92eef53d3844` on 2026-11-11. [QA.md](QA.md) records the exact run, 17 Python tests, 41 native tests, seven UI tests, model hashes and unsigned package checksum.

**Simulator-tested** means only the listed automated cases passed. **Implemented, unverified** means source exists without a matching runtime acceptance test. **Pending** means not implemented. None means physical-device or full-product acceptance is complete.

| Area | Current evidence | Verification or implementation still needed |
|---|---|---|
| Local conversation/history/search/archive/delete | Simulator-tested persistence, search, archive, delete-all, reopen/import/export and streaming ownership/cancellation cases; saved-chat UI relaunch passed | Broader end-to-end UI, interrupted imports and physical-device lifecycle tests |
| Branch/edit/regenerate/copy/share | Branch/edit model tests passed; controls implemented | End-to-end editing, regeneration, selection, copy/share and interrupted UI flows |
| Local searchable memory | Persistence and delete-all cases passed | Add/edit/search/delete memory UI and device privacy checks |
| llama.cpp GGUF inference/download/integrity/storage | Real bundled GGUF produced nonempty output in simulator; import, integrity, path validation and removal tests passed; CI download verified size/hash | In-app download UI, device offline operation, cancellation, larger models, memory pressure, Metal performance and quality evaluation |
| Apple system model | Implemented, unverified, optional | Eligible hardware with Apple Intelligence available |
| Known-offline remote-to-local fallback | Implemented, unverified | Network-transition/device tests; no midstream retry |
| OpenAI-compatible HTTPS endpoint | Parser and endpoint-validation tests passed | Live streaming/authentication/failure/redirect/Keychain integration tests |
| Native SwiftUI/sidebar/settings/appearance | Seven UI tests passed, including navigation/draft preservation and actual screenshot capture | Dark mode, accessibility, more screen sizes and supplied-reference fidelity comparison |
| Markdown/code display | Implemented, unverified | Rendering, selection and accessibility tests |
| Tables/math/syntax highlighting | Pending advanced rendering | Dedicated renderer and visual tests |
| Text/PDF attachments | Text attachment retention/cleanup and bounded prompt inclusion cases passed | File-picker and PDF extraction UI, malformed/scanned PDFs and device tests |
| Image attachments/camera/photo library | Pending | Current text models cannot analyze image pixels |
| Image understanding/generation/editing | Pending capable provider | Do not advertise a text-only model as vision |
| On-device dictation/read-aloud | Implemented, unverified | Hardware permissions, audio interruption and voice playback |
| Hands-free/VAD/background voice/local speech downloads | Pending | Implementation plus device permissions/resource tests |
| Word/spreadsheets/archive extraction/document creation | Pending | Safe parsers, extraction limits and exports |
| Search/web retrieval/citations/research | Pending | Authorized tools, network policy and provenance |
| Repository editing/build tools/agents/schedules | Pending | Tool permissions, approvals and audit history |
| Embeddings/semantic retrieval/encrypted sync | Pending | Local index, encryption and recovery tests |
| Unsigned iPhone IPA | ARM64 Release build and real package verification passed; version 0.1.0, build 1 | Signing/install/refresh and physical-device runtime tests; not release-ready |
| Public release/catalog | Not published | Remaining acceptance and publication gates |
| LiveContainer | Unverified | Real compatibility test |

No service is represented as free without current verified terms. Optional online services can charge or require credentials. No paid API key is required for the local model. Unsupported controls must remain hidden or explain availability without simulating results.
