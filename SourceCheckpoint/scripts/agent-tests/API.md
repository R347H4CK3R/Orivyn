# Local read-only task core contract

`LocalAgentCore.js` exposes frozen global `OrivynLocalAgent` in a bare JavaScript context and guarded CommonJS export for tests. It uses no browser APIs, Node APIs, eval, network, timers or filesystem. Every operation is synchronous. Invalid inputs throw; callers must handle the exception without dispatching a tool.

- `create(goal, uuid)` → serialized state. Goal max512UTF8bytes; UUID normalized lowercase.
- `acceptDecision(stateJSON, modelText)` → state. Strict JSON, no fences, duplicate keys or extra permission fields. An external read-only tool decision produces `status=running` and `pending={operationID,name,arguments}` BEFORE dispatch.
- `recordResult(stateJSON, resultJSON)` accepts exact `{operationID,result}` with bounded plain-text result; stale/duplicate results reject.
- `recover(stateJSON)` changes running→interrupted without executing anything.
- `resume(stateJSON)` requires interrupted, archives the abandoned pending operation and returns ready; it does not replay that operation.
- `cancel(stateJSON)` and `fail(stateJSON,message)` persist clear terminal outcomes. Cancel is idempotent only when already cancelled; answered tasks cannot be overwritten through either API.
- `prompt(stateJSON)` requires ready and returns bounded text for the model, not serialized JSON. Full goal is preserved; a compact index exposes every result step/name/outcome/byte length. A selected <=256-byte page includes step, offset, nextOffset (null at end), endOfResult, totalBytes and text. Offsets count UTF-8 bytes at Unicode scalar boundaries. No claim is allowed about unseen data.

State fields: version,id,goal,status,revision,steps,history,pending,answer,error,internalReads,resultView. States:ready/running/interrupted/answered/failed/cancelled. At most6tool calls; a final answer is still allowed after the sixth result. An answer requires at least one succeeded local tool result; interrupted-only history is insufficient. Answered still means model prose only, not proof of semantic faithfulness or any external action.

Allowed read-only tools:
- get_app_info: arguments{}
- list_models: arguments{}
- search_conversations: arguments{query:string up to256UTF8bytes,limit:integer1…10}
- read_result: arguments{step:integer1…6,offset:integer0…4096}; reads an existing succeeded stored result only. Handled internally by the reducer: returns ready with no pending operation, increments internalReads/revision but not steps. Native must persist and continue its model loop WITHOUT dispatch or recordResult. Maximum102 internal reads is independent of6 external calls, enough to traverse6 full4096-byte results even with multibyte page boundaries. An extra internal read fails the task; answering/cancelling at the limit remains available.

Model decision shapes: `{type:"tool",name,arguments}` or `{type:"answer",text}`. Native tools and provider invocation remain outside this core. Native MUST save running state before dispatch and serialize updates using task ID/revision. A pure reducer cannot prevent replay of an old valid snapshot or authenticate disk contents. Do not accept stateJSON from the model or a tool result.

Bounds: state65536UTF8bytes; decision/result envelopes32768bytes; result/answer4096bytes; error512bytes; JSON depth12; arrays32items. Strict string validation rejects lone surrogates. Prompt worst-case escaping and multibyte paging regression stays under3500bytes. Source API supports Unicode within byte bounds.

Evidence:25actual-code Node tests pass, including execution in bare vm context without web/Node globals. Red/green logs retained. This is not JavaScriptCore/native Swift/iPhone verification or a successful model-task claim.

Paging state: internalReads defaults0; resultView is null or {step,offset}. Newly recorded result selects its first page. Legacy snapshots missing BOTH fields migrate to0 reads and latest succeeded result at0; partial or malformed paging state rejects. Migration validates the old snapshot and increments revision once, making changed serialized bytes acceptable to native CAS persistence. Recover a legacy running state adds a second revision for interruption. Re-reading migrated state does not increment again. Always recover/persist before model inference; prompt returns text rather than a migrated snapshot. Internal tools cannot appear as pending or history operations. Revision maximum160 accommodates bounded paging and recovery. All stored results remain capped4096bytes; paging does not recover data omitted upstream.

Native grammar integration: initial root permits only original external tools; grounded root may also emit read_result with exact args step then offset. Validate against reducer regardless of grammar. New paging prompt/source differs from the earlier model smoke: no model rerun or native verification is claimed for paging. Paging RED/GREEN logs and full Python/VM-suite logs retained.

Conversation search includes titles, messages and stored attachment names/extracted text without opening original files. New results carry evidenceSource: title, message, attachment_name or attachment_text. These are provenance labels, not fact or OCR verification. Verified-plan recovery accepts old results without the optional label and rejects unknown labels/extra keys.
