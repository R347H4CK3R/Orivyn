# Folder memory implementation plan

Goal: import selected folder text locally as reviewable saved archive notes.
Architecture: bounded descriptor-safe scanner, scoped coordinated off-main reader, explicit SwiftUI review, atomic additive SQLite import. Swift6/Foundation/SwiftUI. Spec: ../specs/2026-11-16-folder-memory-design.md.

- [x] Inspect screenshot and existing imports; record unknown actual archive format.
- [x] Failing Foundation tests for absent parser/scanner; implement Unicode-safe chunks, recognized ChatGPT JSON and bounded safe folder traversal.
- [x] Failing SQLite tests for absent atomic import method; reuse existing import transaction for additive content dedupe.
- [x] Add selected-folder picker, cancellation, actual scan progress, explicit review, disclosed limits/errors, and memory navigation.
- [x] Review full branch for provider lifecycle, filesystem attacks and complete memory retrieval.
- [x] Run final Foundation/SQLite/portable suites; distinguish unrelated baseline failures.
- [ ] Native compile, Files-provider selection/cancel and actual large-user-archive acceptance remain separate release gates.
