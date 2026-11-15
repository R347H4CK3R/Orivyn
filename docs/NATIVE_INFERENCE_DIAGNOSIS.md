# Native inference and UI diagnosis

Observed source: dfa998a7604007c331428bafb0e1ba709d346e62.
Run: https://github.com/R347H4CK3R/Orivyn/actions/runs/43649423272
This is an older source revision, not current-head or physical-device acceptance.

The inference job completed the vision, native tools Q8, native tools Q4, and reviewed-plan Q4 gates with exit status 0. General local-agent Q4 returned status 1. The core and UI shards 0 and 2 passed; UI shard 1 failed.

## General agent failure

The actual simulator attachment records a successful search, followed by a final answer containing the returned conversation ID. There was no read_conversation call. The session reported timeout=false, cleanupFinished=true and sessionError=none; inference took approximately 36.3 seconds. Thus increasing the inference timeout does not address this case.

The unreviewed session request requires a tool only until any successful tool result exists. A successful title search therefore permits an answer before message evidence is read. Reviewed read workflows instead derive canAnswer from the approved plan and enforce it before persistence. A general fix must preserve legitimate title-only queries and calculator tasks, and must not infer additional read permission merely from a search result. No heuristic title rewriting, forced unauthorized read, or weakened oracle has been added.

## Composer failure

After returning from Settings, the UI test typed its full fixed phrase but observed only a prefix. XCTest reported the app idle before reading the accessibility value. This alone does not establish whether the cause is input delivery, binding updates, or accessibility observation. The exact equality assertion remains intact; no arbitrary delay or retry was added to hide the failure.

## Remaining gates

Current-source native run 43653937642 and hardened authentication run 43655527605 were queued when this note was written. Authenticated live sync remains disabled. No release or device validation is implied.
