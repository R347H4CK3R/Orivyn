# Selected-folder memory import (development candidate)

This branch adds **Settings → Saved memory → Import a folder**. It is not included in earlier published IPAs. The user picks the already-extracted folder in Files, waits for actual scan progress, reviews counts/skips and the first 20 excerpts, then taps **Add to saved memory**. Cancelling selection/scan or discarding review does not save notes. Imported content stays on-device during import; existing remote-provider use may subsequently send selected memory excerpts, as disclosed in the screen.

Supported inputs:
- UTF-8 `.txt` and `.md`, recursively within the selected directory.
- A ChatGPT `conversations.json` top-level array containing mapping/message/author/content data. User and assistant text are retained with roles and conversation titles, including alternate branches. This is archive content, not verified personal facts or higher-priority instructions.
- Media, ZIP files, arbitrary JSON, hidden/package descendants and common credential filenames are skipped. Filenames are only a precaution, not comprehensive secret detection. Select the intended export folder, **not all of Downloads**.

The ChatGPT parser streams one conversation at a time. It does not load a multi-gigabyte ZIP or entire JSON into memory. Ceilings are 1 GB streamed JSON, 16 MB per conversation/text file, 20,000 directory entries, 40 MB extracted notes and 10,000 notes per scan. The saved collection also has a 10,000-note ceiling. Reaching a ceiling aborts review, with no saved partial import; unsupported/unreadable files are reported as skipped. Original files are never modified. Split archives beyond these limits. Exact-content duplicates are skipped at save time; a whole batch commits atomically or rolls back.

Saved memory browsing is debounced and searched off the UI actor, with 200-note pages. Agent memory search scans the complete loaded snapshot while retaining bounded results. This is literal retrieval, **not exhaustive semantic recall**; only bounded excerpts enter a model prompt. A disk-backed index remains future work.

Verification: 485 Foundation tests and 142 SQLite tests passed on Linux; 152 JS tests passed. Includes an 18 MB synthetic ChatGPT export, no-follow symbolic-link cases, Unicode chunking, invalid/truncated JSON, scan cancellation, cumulative budgets, repeated deduplication, and injected second-write rollback. Native SwiftUI/Files-provider permissions and the user's actual 1,116-item folder remain unverified. Source-only Swift parser checks are not native typechecking or iPhone verification. Python portable aggregate retains four failures/four errors already present on clean build15, documented by the full-library retrieval work.
