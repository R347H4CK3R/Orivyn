# Full backup restoration recovery ledger

Baseline: `3f615b65e073d9464346fffbd28d92a8f5e667ef`, the folder-memory candidate.

The later unpublished archive-coordinator worktree was not available in the resumed environment. This branch reconstructs components incrementally. It does **not** claim that full ZIP import is implemented or released.

## Implemented component

`ChatGPTConversationRestore.convert` converts one JSON conversation record, bounded to 16 MB, into ordinary conversation/message models. It follows only the selected ancestry, rejects broken/cyclic trees, excludes internal/system/tool/private records, preserves explicit dates, and retains unresolved media metadata separately without inventing local asset paths. Completed, failed, and interrupted messages remain distinguishable. Non-UUID IDs require a coordinator-owned durable mapping. Original source records must remain in the preserved archive.

This component does not read the whole ZIP, install attachments, save SQLite records, change user settings, or execute imported instructions. Missing timestamps currently fail closed rather than inventing dates. The coordinator will need an explicit user-visible policy before supporting exports missing dates.

## Remaining integration

1. Recover/rebuild bounded ZIP64 extraction with path/CRC/size/deflate validation and disk capacity checks.
2. Preserve original ZIP and extracted files with SHA-256 manifest, exclusive staging, crash recovery and revalidation before committing.
3. Stream conversations one record at a time; persist stable legacy ID mappings and conversion review.
4. Resolve attachments only from verified archive metadata, preserving unsupported/unresolved material.
5. Commit additive SQLite history/provenance transaction; never overwrite local edits or confuse committed data with a postcommit reload failure.
6. Integrate Settings/Files/review/log/cancellation/relaunch flows, expose retained unsupported data.
7. Run native integration tests and actual device acceptance. No full restore or 1.0 readiness assertion is justified yet.

## Validation

Synthetic data only. No private ChatGPT export has been uploaded or added to this repository. Linux Swift coverage is not an iOS compilation or physical-device result. Current portable Python aggregate retains the baseline four failures/four errors/one skip (271 tests). Full Foundation counts and final review are recorded with the recovery commit report.

Recovery validation: 509 Foundation tests passed on Swift 6.0.3/Linux, including 13 converter tests. The existing unsupported Linux URLProtocol redirect case remains excluded (native gate required). The seven initial converter tests, message-status test, unresolved-media tests and allocation-limit test were observed failing before their corresponding implementation/fixes. Independent review led to preserving interrupted/failed states, unresolved media references, and a 2,048-record unresolved-content ceiling with cancellation checks.

Pre-existing Python failures: `test_engine_uses_tokenizer_aware_preparation`, `test_all_success`, `test_import_ui_discloses_matching_record_replacement`, `test_import_selects_policy_then_cancels_real_picker`. Errors: three `test_explicit_model_gates` cases and `test_bundled_guest_bytes_and_native_allowlist_agree`. These remain unresolved; Foundation success is not overall app acceptance.

Legacy message IDs now use versioned UTF-8 byte-length framed tuple keys, tested with delimiter-colliding IDs. No durable mapping currently consumes this draft API. UI, ZIP acquisition/extraction, durable atomic restore and physical-device verification remain unimplemented on this branch.

Second checkpoint: unambiguous legacy ID framing and `ChatGPTRecordStream` added. The reader bounds file/record/count/nesting, validates records, reads 64 KiB chunks and stops on consumer failure. Consumers must stage only until the complete input passes; callbacks are not commit authorization. 515 Foundation tests passed, including escaped Unicode crossing chunk boundaries. ZIP preservation/extraction are being developed separately and are not yet integrated.

Third checkpoint: original archive preservation integrated. Nine focused tests rerun successfully against integrated source. Source/copy SHA-256 rereads, exclusive staging and manifest publication, parent/file fsync, expected-manifest revalidation and incomplete-copy retention are implemented. Source paths require stable Files-provider coordination and canonical app-private staging. The preservation test module now supports both the isolated Preservation harness and the JarvisEVO app test target; Apple compilation remains unverified.
