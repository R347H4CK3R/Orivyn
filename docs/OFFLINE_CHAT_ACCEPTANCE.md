# Combined actual offline chat acceptance

offline-chat-1 compiled the exact production SQLiteConversationStore, LlamaEngine, LocalPromptBuilder, MemoryContextBuilder and their value types with official SQLite 3.50.4 and the cached matching llama b9049 runtime. The explicit host driver used the actual Qwen2.5-0.5B Q4_K_M weights, not a provider double.

Six checks passed:
1. Seeded conversation, document extracted text and memory reopen through a separate SQLite connection.
2. Reopened history produces the correct follow-up answer and streaming pieces are persisted.
3. Reopened supplied document text produces the correct answer and is persisted.
4. Saved memory loaded from SQLite is selected by production logic and grounds the actual answer.
5. Completed generated responses survive separate-connection reopen.
6. Export/import restores those actual generated conversations and memory exactly.

The driver controls orchestration and invokes real components; it does not execute SwiftUI AppModel. It uses supplied extracted text rather than native document import. Reopen is a separate connection in one process, not a crash/power-loss or OS restart test. Native UI, iOS system SQLite/file protection, Apple frameworks, device installation and general language-model quality remain unverified.

Source/header/model/library hashes, commands, toolchain versions and stage exit codes are preserved locally. No server, downloads, paid CI or release is involved. Every owned subprocess is reaped; engine resources are explicitly unloaded.

## Edited branch and conversation management
offline-chat-branches passed eight checks. The added path branches the actual persisted original conversation through a user turn, edits its robot name from Copper Owl to Amber Fox, and asks the actual engine again. It generated the new name while an exact reread of the original conversation stayed unchanged. The generated branch was renamed, archived, found by literal title search, excluded from active results, and included unchanged in the backup round-trip. These are real conversation value/store/model operations orchestrated by the driver; UI buttons and AppModel branching remain an unexecuted native integration gate.

## Stricter factual acceptance
The host integration now requires the complete trimmed, case-normalized answer to equal each requested codename. Merely including the expected name inside a contradictory response no longer passes. Raw successful answers are printed. A fifth conversation supplies an attachment without extracted text and explicitly requests `Unavailable` instead of guessing; its real model response must match, persist and survive the same five-conversation backup roundtrip. This strengthens evidence rather than proving arbitrary factual reliability. No hosted service or fabricated answer is used.

`offline-exact-unavailable` passed9 real engine/SQLite checks. Actual complete answers were Copper Owl, Cobalt Finch, Silver Badger, Unavailable and Amber Fox. Compilation/runtime processes exited0 and were reaped;135 Python tests passed. Private test checkpoint548c34386d70ac5ccb2f1817905404932704445a verified exactly. This does not execute native AppModel or prove arbitrary document accuracy.

## Larger cached model cross-check

The unchanged exact-answer offline harness also passed all nine integration checks with the cached Qwen2.5-1.5B-Instruct Q4_K_M model. It produced the five required whole answers for persisted history, extracted document text, saved memory, unavailable attachment, and edited branch; rename/archive/search, separate database reopen, and exact backup/restore also passed.

Evidence: `offline-exact-15b/` contains the exact command, binary/model hashes, source-parity reuse record, full inference log and exit status 0. The existing compiled exact LlamaEngine/SQLite driver was reused only after checking current source hashes. No new model download or billing occurred. This remains a Linux host integration proof, not SwiftUI AppModel, iPhone inference, general model accuracy, or release readiness.
