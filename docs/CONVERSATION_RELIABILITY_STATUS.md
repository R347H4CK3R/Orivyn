# Conversation management reliability candidate

Source implemented and reviewed, native compilation/execution still pending.

- Rename/archive now await durable storage before visible metadata changes, return real success/failure, and update metadata only. They refuse edits to the currently streaming conversation without stopping or losing its tokens; unrelated conversations can still be changed.
- Rename and message-edit sheets await success and retain input on failure. Controls/dismissal are disabled during saves.
- Branch/edit/regenerate capture their source conversation. A switched context cannot accidentally act on a different branch sharing message identifiers. Saved branches do not override later navigation or model changes; no response starts in that changed context.
- Regenerate requires an assistant target and uses the correct preceding user turn. Missing providers are reported before creating a misleading generation branch.
- Original history stays intact. Unrelated composer drafts and pending attachments are no longer cleared when creating a branch.
- Literal case/diacritic-insensitive conversation search includes attachment names and already-extracted text, without opening originals or sending a search to a provider. Queries are bounded with visible feedback.

Eleven new native regressions are authored: five metadata cases using real SQLite failure triggers and controlled streaming; five branch/edit/regenerate/source-context cases; one search case. Controlled-provider tests do not prove model quality. All native tests remain unrun. Structural tests verify durable-before-visible mutation, awaited editors, source guards and composer preservation only.

Portable gates:101 Python,60 agent/router/draft JavaScript,39 VM JavaScript pass. Source review found no further concrete API/logic defect. No paid CI, source publication or IPA release occurred.

## Follow-up UI integration review
New-conversation persistence now returns success only after saving/selecting the new chat; history closes/navigates only on that success. Failed insert keeps the current composer and history visible. An authored native SQLite-trigger test checks failure/retry (not run here). History also explicitly discloses oversized queries instead of silently treating a rejected >1,024-byte search as no results. Two new source-contract checks observed failures before fixes and pass afterward. Full portable suites: 115 Python, 60 agent JavaScript, 39 VM JavaScript. Swift/native gate remains unrun.
