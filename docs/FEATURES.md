# Feature and compatibility matrix

Status meanings: **implemented, unverified** means source exists but native execution has not passed. **pending** means not implemented. No category below is a completed acceptance claim.

| Area | Source status | Verification still needed |
|---|---|---|
| Local conversation/history/search/archive/delete | Implemented, unverified | Restart, import/export, concurrent streaming tests |
| Branch/edit/regenerate/copy/share | Implemented, unverified | UI and interrupted-flow tests |
| Local searchable memory | Implemented, unverified | Memory UI and delete-all tests |
| llama.cpp GGUF inference/download/integrity/storage | Implemented, unverified | Real prompt, offline run, cancellation and memory pressure |
| Apple system model | Implemented, unverified, optional | Eligible device and Apple Intelligence availability |
| Known-offline remote-to-local fallback | Implemented, unverified | Network transition/device tests; no midstream retry |
| OpenAI-compatible HTTPS endpoint | Implemented, unverified, optional | Streaming, failures, redirect refusal and credential handling |
| Native SwiftUI/sidebar/settings/appearance | Implemented, unverified | UI tests and supplied-reference comparison |
| Markdown/code display | Implemented, unverified | Rendering, selection and accessibility |
| Tables/math/syntax highlighting | Pending advanced rendering | Dedicated renderer and visual tests |
| Text/PDF attachments | Implemented, unverified | File-picker/extraction tests |
| Image attachments/camera/photo library | Pending | Current text models cannot analyze image pixels |
| Image understanding/generation/editing | Pending capable provider | Do not advertise text-only model as vision |
| On-device dictation/read-aloud | Implemented, unverified | Permissions, audio interruption, voice playback |
| Hands-free/VAD/background voice/local speech downloads | Pending | Device permissions and resource tests |
| Word/spreadsheets/archive extraction/document creation | Pending | Safe parsers, extraction limits and exports |
| Search/web retrieval/citations/research | Pending | Authorized tools, network policy and provenance |
| Repository editing/build tools/agents/schedules | Pending | Tool permissions, approvals and audit history |
| Embeddings/semantic retrieval/encrypted sync | Pending | Local index, encryption and recovery tests |
| Unsigned IPA/catalog/release | Pending verified build | ARM64 package, hash, native tests and release gates |
| LiveContainer | Unverified | Real compatibility test |

No service is represented as free without current verified terms. Optional online services can charge or require credentials. Unsupported controls must be hidden or explain availability without simulating results.
