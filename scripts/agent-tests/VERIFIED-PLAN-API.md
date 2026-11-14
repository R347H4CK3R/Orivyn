# Verified local reads: deterministic core

Resource `VerifiedLocalPlan.js`, global `OrivynVerifiedLocalPlan`, guarded CommonJS export for tests. No model, NLP routing, eval, native tools, filesystem, browser APIs or network. Native owns all data reads and persistence. This is deliberately separate from the unreliable experimental autonomous model loop.

All methods return JSON strings; invalid inputs throw:

- `create(requestJSON, uuid)`: exact request `{appInfo:Bool, installedModels:Bool, searchQuery:null|String,memoryQuery:null|String}`. At least one selected read. Query nonblank, <=256 UTF-8 bytes; UUID lowercased.
- `next(stateJSON)`: only ready. Records running pending intent before dispatch. Order is selected app-info, selected installed models, selected conversation search(limit10), selected memory search(limit10). Eight total attempts max, at most four successful reads. Returns failed after budget exhausted, without dispatch.
- `record(stateJSON, envelopeJSON)`: exact `{operationID:String,resultJSON:String}`. Only running and matching operation ID. Validates result JSON against the corresponding native LocalReadTools schema, stores full structured result. Advances to ready or complete after final selected read. No model prose.
- `recover(stateJSON)`: running becomes interrupted; other states remain unchanged. No replay.
- `resume(stateJSON)`: interrupted only; drops abandoned pending intent and returns ready. Next call allocates a NEW `uuid:attempt` operation identity for retrying the same selected read.
- `cancel(stateJSON)`, `fail(stateJSON,message)`: preserve earlier evidence and clear pending. Terminal states cannot be overwritten; repeated cancel on cancelled is idempotent.
- `report(stateJSON)`: works for every status. Returns `{status,complete,verifiedReads,requestedReads,evidence,limitations}`. `complete` is true only for complete status. Partial/cancelled/failed reports remain explicit.

## State / Swift contract

Exact state fields:
`version:1,id:String,request:Object,status:String,revision:Int,attempts:Int,completed:Int,pending:Object|null,evidence:Array,error:String|null`.

Statuses: ready/running/interrupted/complete/failed/cancelled.
Pending: `{operationID:String,name:String,arguments:Object}`.
Evidence entry: `{name:String,arguments:Object,result:Object}`.
Arguments: `{}` for app/models or `{query:String,limit:10}` for search. Argument JSON key order is irrelevant; extra fields reject.

Native MUST save running state before dispatch, serialize updates by UUID/revision and retain interrupted tasks until explicit Resume. Do not accept snapshots from model or untrusted tools. Validation detects malformed state, not cryptographic forgery or stale replay of a valid old snapshot. Native CAS storage owns replay protection. Native tools remain local-only, read-only and synchronous; no resource lease or inference model is required.

## Native result schema

App: `{app:String,assistant:String,repository:String,repositoryAccess:String,capabilities:[{id:String,status:String}]}`; max24 capabilities.
Models: `{models:[{id:String,name:String}],totalInstalled:Int,truncated:Bool}`; list length must equal min(totalInstalled,10), truncated must equal totalInstalled>10.
Search: `{matches:[{id:UUID,title:String,excerpt:String,excerptMayBeTruncated:Bool}],searchedConversations:Int,searchLimited:Bool}`; max10 matches, searched<=500, limited implies searched500. Native title max96 UTF-8 bytes and excerpt160 bytes preserved exactly.

The complete structured result is retained, including final/tenth matching records and explicit native markers. No 256-byte model prompt excerpt/paging applies here. Conservative report limitations disclose the native source's missing title/name truncation markers, first24 capabilities, first10 models/matches, first500 searched conversations. This cannot recover omitted upstream data or prove the correctness of native data. “Verified” means selected read returned schema-validated data, not AI verification of its contents.

Limits: request4096 serialized bytes; resultJSON16384; envelope32768; state65536; revision40; eight attempts; four successful reads. Strict JSON rejects duplicate/reserved keys and invalid Unicode. Errors<=512 bytes.

## Evidence

17 actual-code tests in verified-plan.test.cjs cover exact mixed app/model facts, complete tail records, strict request and result schemas, bare JS execution, inert hostile text, cancellation, stale/duplicate result rejection, interruption/retry IDs, eight-attempt budget, partial reports, restoration validation and truncation flags. RED/GREEN logs retained. Native integration/device testing remain separate gates; no model or device claims follow from these fixture tests.

Saved-memory schema and backward-compatible three-key requests: see MEMORY-READ-EXTENSION.md.

## Conversation payload preservation correction

Conversation titles/excerpts now preserve stored C0 controls verbatim as inert JSON data, matching memory excerpts. Type, valid Unicode and96/160 UTF-8 byte limits remain strict; UUID, cardinality, booleans, queries and commands remain unchanged. Ten maximal C0 title/excerpt results serialize to16,412 bytes (outer envelope19,190), so16KiB was insufficient by28 bytes. Only search_conversations resultJSON increases to20,480 bytes; other results remain16,384, outer envelope32,768 and state65,536. Native search_conversations must use20,480 encoded output cap. No truncation/sanitization is introduced. Regression checks exact record/report/recovery, Unicode limits, per-tool budget isolation and outer envelope bound. RED/GREEN logs conversation-controls-red.log, conversation-resultcap-red.log and conversation-controls-green.log.
