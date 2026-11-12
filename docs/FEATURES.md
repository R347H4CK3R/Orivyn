# Feature and compatibility matrix

Evidence applies to application source `1be1c99cb6ca1c68b5425a6cdfb0240963768b16`, tested by CI `65ae165a7183add9a23025442567c60ac437f90a` on 2026-11-12. [QA.md](QA.md) records the exact run: 34 Python, 78 native and 16 UI tests, zero skips, model hashes and candidate 2 package checksum. Later documentation does not change the tested source.

**Simulator-tested** means only the listed cases passed. **Implemented, unverified** means source exists without matching runtime acceptance. **Pending** means not implemented in this candidate. No status establishes physical-device or full-product acceptance.

| Area | Current evidence | Verification or implementation still needed |
|---|---|---|
| Local conversation/history/search/archive/delete | Persistence, search, archive, delete-all, reopen/import/export and streaming ownership/cancellation cases passed; saved-chat relaunch and sidebar archive UI passed | Broader end-to-end flows, interrupted imports and physical lifecycle tests |
| Branch/edit/regenerate/copy/share | Branch/edit model tests passed; controls implemented | End-to-end editing, regeneration, selection, copy/share and interruption tests |
| Local searchable memory | Persistence, backup and delete-all cases passed | Add/edit/search/delete memory UI and device privacy checks |
| llama.cpp GGUF inference/download/integrity/storage | Actual Qwen generation passed; real app download → verified installation → selection → completed reply → relaunch passed; integrity/path/removal tests passed | Physical offline operation, cancellation, Metal performance, memory/thermal behavior and additional models |
| Apple Foundation Models | Compiles; unavailable state handled | Eligible hardware, availability transitions and real generation |
| Optional HTTPS OpenAI-compatible provider | Endpoint/parser/model tests passed; unavailable-provider UI does not invent a response | Real endpoint authentication/streaming/failures, redirect refusal and Keychain verification |
| SwiftUI/sidebar/settings/appearance | 16 UI tests passed including left drawer, draft preservation, row archive, settings, compact composer, light/dark and multiline captures | Accessibility, additional screens and deeper reference fidelity |
| Markdown/code display | Basic source implementation; not separately accepted by rendering tests | Rich rendering, selection and accessibility |
| Tables/math/syntax highlighting | Pending advanced rendering in candidate 2 | Separate work in progress is not part of this IPA |
| Text/PDF attachments | 17 service and five app-flow tests passed; real inference from imported text passed; repeat Files-picker cancellation passed | Broader real document/device workflows and additional formats |
| Image attachments/camera/photo library | Pending in candidate 2 | Separate work in progress must be built and verified before attribution |
| Image understanding/generation/editing | Pending capable provider | Current text-only local model does not analyze image pixels |
| On-device dictation/read-aloud | Source implemented; 14 simulated permission/race/interruption tests passed | Real microphone, permission dialogs, recognizer availability, routing and playback on hardware |
| Hands-free/VAD/background voice/local speech downloads | Pending in candidate 2 | Separate implementation and device/resource acceptance |
| Word/spreadsheets/archive extraction/document creation | Pending | Safe parsers, limits and exports |
| Search/web retrieval/citations/research | Pending | Authorized tools, network policy and provenance |
| Repository editing/build tools/agents/schedules | Pending | Permissions, approvals and audit history |
| Embeddings/semantic retrieval/encrypted sync | Pending | Local index, encryption and recovery tests |
| Unsigned iPhone IPA | ARM64 Release package verified; version 0.1.0, build 2, iOS 26.0 minimum; app and llama framework unsigned | SideStore signing/install/refresh and physical-device runtime tests; development candidate only |
| GitHub release/catalog | Not published | Remaining acceptance and publication gates |
| LiveContainer | Unverified | Real compatibility test |

No service is represented as free without current verified terms. Optional online services can charge or require credentials. No paid API key is required for the local model. Unsupported controls must remain hidden or explain availability without simulating results. Original branding and reference-informed layout do not imply OpenAI affiliation or exact feature/pixel parity.
