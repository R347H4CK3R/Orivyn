# Local read-only agent candidate

Not published, native compilation and iPhone verification pending. Target 1.0.0 remains incomplete. This is not a self-repair agent or unrestricted automation.

Implemented source: bounded trusted-JavaScript state machine hosted by JavaScriptCore; local llama inference with a bundled JSON/tool grammar; private protected atomic task records with revision checks; three tools that read app metadata, installed model names, and matching conversations. Running intent is saved before tool dispatch. Interrupted work requires explicit resume and does not replay a pending operation. Cancellation and resource pressure keep the heavy-work lease until model unload finishes. Test storage is separated from normal app storage. Corrupt task records are retained and reported without hiding healthy records.

The first decision must choose a tool. An answer requires a successfully recorded result. Grammar/schema validation does not establish semantic truth. Results and user goals remain untrusted data. There is no external networking, arbitrary plugin execution, file editing, messaging, repository access, code patching or automatic release capability in this agent.

## Evidence

- 25 portable JavaScript agent tests passed.
- 91 repository Python tests passed (including structural contracts, not native execution).
- 39 production VM JavaScript tests passed.
- Actual Qwen2.5 1.5B Q4_K_M local CPU inference using the pre-paging effective grammar selected tools and produced grounded responses for two **synthetic fixtures**: app metadata and conversation search. Final times 8.34s and 4.82s. This does not prove native app tools or iPhone performance.
- Earlier free-form inference failed strict JSON validation or invented answers. Those failures were retained; no permissive parser repair was introduced.
- All local smoke servers are stopped.

Native unit/UI tests have been authored and included in the manual gate, but have **not run**. Explicit grammar resource packaging and CI portable-test wiring were added after a failing structural contract test. Swift compilation, Swift-to-llama grammar ownership, JSCore execution, actual application tool reads, persistence/relaunch UI and memory/thermal lifecycle remain native gates. Do not publish this as completed 1.0.0.

Run `bash scripts/run_virtual_desktop_gate.sh` only on an available suitable Mac with sufficient free capacity. This script does not dispatch cloud builds or enable billing. No additional paid CI is authorized.

## Follow-up review repairs

All successful result bodies are now addressable through bounded reducer-only `read_result` paging, with an all-result index and explicit UTF-8 offsets/end markers. Up to102 internal page reads cover six full Unicode4096-byte results without consuming the six native-tool calls. These transitions persist before continuing inference; they never dispatch a native tool. Latest grammar/prompt revision has portable tests but has not repeated the real-model smoke.

Explicit Archive and Restore controls preserve task bytes, refuse overwrites and free active-task slots. Active records remain capped at100; archived records at10000, with only50 loaded per archive page. A native regression covers full active capacity, archive, failed restore into full capacity and successful restoration. It is authored but unrun. No records are automatically deleted.

Manual native gate now stages the pinned test-model resource and enables native test timeouts. It still does not start any cloud run.

Final review found and repaired a migration revision conflict (actual reducer red/green) and cross-session archive resurrection risk (shared lease guard plus store refusal to recreate archived IDs). Native two-session cancellation/archive and migration/store regressions are authored but not run.

## Current-source model acceptance failure

A second actual Qwen2.5 1.5B smoke used the paging revision. Both cases failed semantic acceptance: a combined app/model task skipped list_models and called the assistant name an installed model; a tail-result task did not request read_result and used filler as the answer. Raw records are retained in the local paging-current evidence directory. No parser weakening, answer replacement or retries concealed these failures. The server was stopped. This is an open reliability blocker, not a passed agent acceptance gate. The UI warns that completed answers can be wrong and exposes tool records.

One stronger-system experiment also failed both cases (swapped app/model identity and skipped paging). Production prompts were not changed to hide the failure. Evidence retained; server stopped.

A distinct cached Qwen3 1.7B Q8_0 comparison also failed both cases, using exact native `llama_chat_apply_template` behavior, production system, current grammar, CPU2/context2048. It substituted a fixture version for an installed model and skipped paging. No retries/downloads; server stopped. Evidence retained under paging-qwen3-native-template. Reliable autonomous multi-tool reasoning remains an open acceptance failure for both tested models.
