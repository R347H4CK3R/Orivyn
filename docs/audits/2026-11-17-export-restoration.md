# Whole-export restoration audit after build 20

Scope: source inspection and synthetic records only. No private user archive was inspected. Build 20 resource acceptance does not prove complete export fidelity.

## Confirmed boundaries

- `ChatGPTConversationRestore` walks only the `current_node` ancestor chain. Alternative branches remain in the preserved ZIP, not separate chats.
- System/tool roles, private/hidden records, non-final assistant channels and tool recipients are deliberately not activated. Their exclusion must remain intact.
- Before this candidate, only `text` and `multimodal_text` contents were activated. A synthetic visible final `code` record with explicit `text` was omitted, including its readable code. The narrow candidate restores that explicit text as inert history after the unchanged visibility guards. It does not execute code, infer missing text, or support arbitrary content types.
- Unknown/audio/video content types remain in the original archive only. Their nested media references do not enter the unresolved plan, so `unresolvedCount` is not a count of every missing media asset.
- `ArchiveAttachmentAssociation` has no production caller. Its exact-mapping planner is tested infrastructure, not functioning media restoration.
- The archive service retains unresolved JSON references in `plan.json` and files/hash inventory beside the preserved original. SQLite archive commit receives only conversations and rejects nonempty attachments. The review shows aggregate counts, not per-message media inventory.
- Existing conversations are preserved rather than replaced; importing a newer export does not silently merge over local conversation edits.

## Recommended next media step

First expose a read-only, bounded, per-message inventory of retained/unlinked media and unsupported content, without executing metadata or fetching URLs. Then support only explicit source-ID to exact-relative-path mappings or a user-reviewed mapping. Do not guess from basenames, suffixes or URL resemblance.

Activation requires durable archive-scoped asset identities, root-relative no-follow copy and hash/size revalidation, atomic receipt/association persistence restricted to newly imported conversations, and clear handling for already-present conversations. Keep original bytes. Missing or ambiguous mappings stay unresolved. Reuse scoped read buffers in the currently unused association verifier before activating it.

Opaque association is not a media decoder: existing attachment imports support image/PDF/text up to 10 MB, while the association planner allows opaque files up to 512 MB. MIME, ownership/provenance and runtime format support must be verified before using normal attachment previews.

## Verification status

The code-text regression was observed failing before the implementation. Local regression and independent review are recorded separately. No new native build, physical-device acceptance, complete-media restoration or private-archive success is claimed by this audit.

## Build 21 candidate: read-only retained-reference inventory

The candidate adds a separate inventory that can inspect ready or committed retained preparations without making committed jobs eligible for restore again. It validates the exact review/state/original-hash binding and stored plan hash before decoding, then rechecks state and plan integrity before returning a page. Only conversation title, message index/identity and reference-category counts are displayed. Opaque JSON, paths and arbitrary source labels are not displayed or followed. Duplicate or orphan identities fail closed.

Pages show at most 50 messages, with explicit totals and next/previous navigation. This is bounded display pagination, not constant-memory streaming: each page decodes the entire bounded 50 MB plan and groups up to 20,000 references. The app releases local model memory before this read; Darwin temporary objects are scoped. A synthetic near-limit plan is tested in a fresh host test process under a strict 256 MiB high-water limit. Physical-device memory behavior remains unverified.

The UI explicitly says counts cover only supported visible reference records, not every missing media item or distinct file. Existing local history may differ from the retained archive. No mapping, copying, attachment activation, download or execution was added. Durable attachment association remains deferred until explicit mappings and all ownership/transactional requirements can be met.
