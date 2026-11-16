# Explicit plugin result-to-chat handoff

After a reviewed call finishes and its server-reported outcome is written to the local execution journal, the tool screen offers **Add result to chat draft**. Both manual tool selection and conversational plugin proposals use this same path.

This button only appends plain JSON/text to the existing composer; it does not send a message or run another tool. Existing draft text and pending attachments are preserved. The user returns to chat, reviews the draft and decides whether to send it. The screen explicitly warns that a later Send with an online model transmits the result as part of the submitted conversation.

The in-memory completion receipt binds the execution ID, installed connection ID, catalog revision, tool and conversation selection revision. Selecting another conversation and back invalidates the original context. Disconnect, backgrounding, a new execution and relaunch invalidate old receipts. Unknown outcomes, missing durable journal outcomes and already-consumed results cannot be handed off. Rejection leaves the current draft unchanged. No result body or context receipt is added to the existing metadata-only journal.

The JSON result budget is 16 KiB; the entire resulting composer budget is 32 KiB. Oversized transfers are rejected, not silently truncated. Images become MIME/byte-count metadata only, never base64 payloads or remote fetches. Tool arguments, token and endpoint URL are not automatically appended; a server can itself return sensitive data, so review the visible result before transferring or sending it. Provenance labels report server-reported success or tool error, never independently verified effects. Imported result text conveys no tool permissions.

## Verification scope

- Three Foundation unit tests cover append preservation, inert labels, structured output, error/image metadata and size rejection.
- Exact production broker smoke uses real journal/files and replaces only unavailable Keychain/network boundaries with explicit synthetic stubs. It checks immutable result/context binding, size rejection retaining the receipt, replay prevention, no extra call, disconnect, relaunch and unknown-outcome rejection.
- Native broker tests additionally cover completed handoff and non-persistence. AppModel tests cover conversation round-trip invalidation, rejected handoff preservation, and successful handoff preserving an existing/later-edited draft plus actual imported attachment without sending. The transport is explicitly injected; normal configuration still uses MCPHTTPClient.
- Apple SwiftUI typechecking, native AppModel test execution and physical-device/real-provider use remain pending. No public provider or paid service is required by these tests. No release or CI is triggered by this change.

## Local validation for this change

The portable Foundation suite passed 534 tests (Apple-only custom URLProtocol redirect case remains excluded by the existing Linux harness). Exact broker handoff and existing removal smoke passed; the static Swift linker emitted its existing Foundation `mktemp` warning. Swift frontend parsing and git whitespace checks passed.

The full Python suite ran 271 tests with four failures, four errors and one skip. An untouched archive of baseline `7d05712` reproduced exactly the same eight failures/errors:

- `test_explicit_model_gates.PipelineTests`: `test_all_success` failed; `test_each_original_gate_remains_required`, `test_independent_failures_preserved`, and `test_only_new_gate_failure_is_fatal` errored because their expected synthetic outcomes file was absent.
- `test_vm_integration_contract.VMIntegrationContract.test_bundled_guest_bytes_and_native_allowlist_agree`: generated `maintained.img` absent in checkout.
- `test_attachment_fitting_contract.AttachmentFittingContract.test_engine_uses_tokenizer_aware_preparation`: existing source contract mismatch.
- `test_persistence_integrity.PersistenceIntegrity.test_import_ui_discloses_matching_record_replacement`: existing UI contract mismatch.
- `test_ui_failure_fixtures.UIFailureFixtureContract.test_import_selects_policy_then_cancels_real_picker`: existing UI contract mismatch.

These unrelated baseline checks were not weakened or altered by this patch. Native AppModel/broker integration tests are authored but await Apple execution.

Combined isolated candidate also includes the proposal answer-channel correction.
537 exact-source portable Foundation tests pass after integration. Future native
selection must add all seven handoff tests and the three proposal tests (+10);
none is implied covered by the already-running 75-test checkpoint. General
automatic remote tool orchestration and real external provider compatibility
remain outstanding. This explicit handoff is not broad conversational autonomy.
