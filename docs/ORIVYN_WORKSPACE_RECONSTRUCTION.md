# Reconstructed Orivyn workspace source

This is a reconstruction from the retained implementation context of the earlier Orivyn work, **not a byte-identical recovery of lost local commit 079b849**. The starting 97 files were independently recovered against Jarvis-EVO source commit `f4ac85877bfa707061a3c6cd902412be65cff34e`. Native build and runtime results for this reconstruction must be collected separately; historical results do not verify it.

## Source restored

- Reference-inspired navigation for chat, Scheduled, Space, Customize, Studio, Sites, Projects, Plugins and Images. Missing backend capabilities are labeled unavailable rather than simulated.
- Real local project membership, pinned conversations and favorite attachments. Removing a project keeps conversations. Invalid/corrupt workspace records are preserved and writes blocked. Existing settings under the former 4,000-character instruction limit remain editable after the new 512-byte save limit.
- Space/Images use actual saved attachments and the established trusted file-resolution service. Their view identities are distinct so a Documents filter cannot carry into Images.
- Response preferences are part of actual generation requests. New custom text is limited to 512 UTF-8 bytes, and the real local tokenizer separately limits system context to half the available input budget with actionable Behavior/memory guidance. No silent truncation of custom instructions.
- A single LlamaEngine is shared by local providers belonging to AppModel. Its existing model-URL replacement frees the previous retained resources and its busy guard prevents overlapping streams. Physical-device memory and cancellation behavior still require testing.
- User-reviewed GitHub suggestion drafts and text export. Only explicit entered text is sent, and the app does not embed GitHub credentials or automatically submit issues or publish updates.
- Orivyn display strings and a new native SVG orbital-O icon rendered to an opaque 1024×1024 RGB PNG. The original J SVG is preserved. This is newly reconstructed artwork, not the missing earlier generated concept.
- Build number 4 in both Info.plist and project.yml, retaining marketing version 0.1.0. Bundle ID, scheme/module, Application Support path, conversation format, model manifest and Keychain identity stay unchanged.

The model catalog is a separate integrated change with its own publisher/template evidence under `docs/model-catalog/`. Model metadata/template validation does not prove full-weight inference or iPhone performance.

## Verification boundary

Native tests are authored for persistence/corruption/migration, preference propagation, shared runtime identity, feedback destination validation, navigation draft preservation, route filter reset and project relaunch. They were not executed by the reconstruction worker because xcrun/Xcode is absent from that workspace. Packaging tests have a separate executable Python suite. Four branding checks were observed failing before the restored implementation and passing afterward.

Before release: independently review the combined source, run native and UI tests on Xcode 26 with real weights, inspect actual screenshots, exercise model switching/cancellation/unload, validate the physical iPhone memory budget, build/checksum the exact ARM64 IPA and verify signing/installation. Do not present this source reconstruction as an already-tested IPA, pixel-perfect reproduction or full backend parity.
