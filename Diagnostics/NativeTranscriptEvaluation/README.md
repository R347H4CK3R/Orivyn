# Native transcript and engine development evidence

This is an experimental bounded local read workflow, not general autonomous tool use.
The production app does not define ORIVYN_NATIVE_TRANSCRIPT. Behind that opt-in
flag, LocalAgentSession now selects this route only for a supported explicitly
approved contract and the pinned Q4 model; other plans/models retain the existing
reviewed route. AppModel and the approval UI were not changed.

## Preserved baseline failures

Source ba213d629dd1046ec24ab97ed9651f47d601a9b0 used the actual Swift transcript and strict
response adapter, unchanged JavaScript reducer and synthetic SQLite execution, but
external pinned llama-completion inference. Run 43677019662 passed 3/5. The known
multi-envelope/fabricated-ID response remained rejected.

Source 592ed77fb30efe75f32d8e8b0d3b8d584243bef7 added explicit caller-owned exact-title and
message-index scope, validated during history replay and before returning decisions.
Run 43679477651 passed portable Swift/golden/mutation checks but only 3/7 real-model
cases. Artifact 14148336049, ZIP SHA256
37b8ea130efb1da674e316d631e384510081695109e6eab19c28f9a6e8904c9b.
Maple, Willow and independent Cedar passed. Orchid attempted index 2 instead of 1,
and the strict adapter rejected it before dispatch. Birch, hostile Hazel and
independent hostile Elm read the correct message but emitted a stray closing think
tag in the answer and were rejected. No rejected output was repaired or accepted.

The follow-up grammar constrains one tool envelope to the explicit scope and
requires plain-text final answers without angle-bracket protocol starts. It never
contains an expected code or saved message text. The existing strict adapter,
unchanged reducer, fresh random IDs/codes, all seven cases and success criteria
remain required. This is a narrower approved workflow, not improved general
autonomous reasoning. Grammar generation is not user consent.

## Actual production engine seam

Source 706348c703214c5e5f8f2513a149cb40f3a96dd4 adds an opt-in internal request to the
actual LlamaEngine actor. The engine verifies SHA256 of the file bytes and the
loaded model's template, tokenizes the complete transcript with the loaded
vocabulary, reserves all 384 output tokens in the 2048-token context and rejects
overflow without trimming. Native text is buffered; only EOG followed by strict
adapter acceptance yields a reducer decision. Native token-cap or validation
failure yields no partial decision. Other models are rejected for this mode;
ordinary chat retains its existing route.

The initial 706348 path-stat-plus-reopen hash had an ownership limitation under
concurrent source replacement. The follow-up copies bytes from one source handle
into an engine-owned UUID directory (0700), hashes the copied stream, checks the
pinned byte count and SHA, closes the write handle, makes the copy read-only (0400),
and loads only that verified file. No application writer receives its path.
LlamaResources owns the directory until model release, and deletes it afterward;
failed copies are removed. Switching sources releases the old copy before creating
a new one, bounding owned-copy storage to one 1,282,439,264-byte model. Ordinary
source metadata is only a cache hint; inference uses the retained private copy.
A crashed process can leave a temporary directory; crash-start scavenging and
storage-pressure/device tests are still required before enabling this route.
Caller-supplied scope is not consent: it must come from separately reviewed
authorization, with reducer validation and execution policy retained.

Run 43680016545 at 706348 passed all four initial actual-engine probes and 6/7 workflow cases; Orchid remained rejected before its required read. Artifact 14148675323, ZIP SHA256 c1244989fd425edb595d8f8ee7f373f40a69204ae279c33e37257a845c55a1df. This baseline did not yet use constrained native grammar or private model copies.

The engine CI builds the exact production Swift actor with real pinned Swift Crypto
3.12.3 (commit e8d6eba1fef23ae5b359c46b03f7d94be2f41fed) and pinned llama.cpp, on
Ubuntu CPU. It tests conflicting-mode rejection, actual tokenizer overflow,
modified-valid-GGUF hash rejection and ordinary chat, then the same seven workflow
cases. The actor EOG check is the completion evidence here; the external CLI marker
and performance-count checks belong only to evaluate.py.

No Apple compilation, simulator, iPhone behavior, permissions UI, app dispatch,
cancellation under the new native mode or complete release acceptance is established
by these Linux diagnostics. No model or user data is uploaded to a model provider.

## Approved-contract route (follow-up gate)

Run 43680786562 at 06580f68c52fa1e3db28172095a0ca9661c47f74 passed all six portable
Swift tests plus golden/mutation checks, all five actual-engine boundary/snapshot
probes, and all seven real Q4 synthetic workflows. Artifact 14148453564, ZIP SHA256
677ff92b131657c99d1bbecc47e88d440dc0c71a81d64a442fa0688f3e32423c.
This gate used caller-supplied diagnostic scope, not application approval UI.

The follow-up derives scope only from an already-approved readPlan with
approvalRevision=0, conversation_read, query equal to exact title, and one index.
Its search limit is 10 to match the unchanged reviewed reducer. The original
persisted state and approval metadata are never rewritten. The session first
derives LocalReadWorkflowPolicy from actual current conversations, and retains
reducer acceptance, durable pending-write-before-dispatch, and source policy
validation before execution/answer persistence. Unsupported plans and other model
descriptors use the existing reviewed route. A loaded-template mismatch falls back
before any native output/tool dispatch; malformed native responses do not fall back.

For this reviewed route, the final response is constrained to the existing answer
decision JSON and then strictly parsed. Literal angle brackets in answer values
remain representable; duplicate keys, protocol markers and text after the complete
JSON root are still rejected. No expected answer enters the grammar.

The next Linux gate uses createReviewed/decisionPolicy from the unchanged reducer,
the actual engine, all seven previous cases plus untouched Pine first-message and
hostile Rowan fifth-message holdouts. Pine exposes the code in search but still
requires the approved actual read. A sixth actual-engine probe cancels after private
snapshot sealing and checks that no partial decision or owned directory survives.

The main production generic-task failure remains separate: this narrow approved
workflow does not fix or establish general autonomy. Apple full-app compilation,
native-route UI approval checks and physical-device validation are not implied.

## Verified reviewed gate and user flow

Source 460bfe1b6e80a9b0e066178c893ec9b854de6941 passed run 43682252962:
8 Swift tests plus exact-template goldens and mutation checks; 6 actual-engine
probes (including source replacement, cancellation and cleanup); 9/9 real Q4
reviewed-policy workflows. Every workflow performed its required message read
before returning the freshly generated code, with no broadened read accepted.
Artifact 14148987073 has ZIP SHA256
c93b418f600c1280d95f26756e3c28c29ba5c3d358317d96da339ef585db898f.
The SHA-checked synthetic evidence is preserved in
docs/evidence/native-reviewed-460bfe.json. Earlier failures remain beside it.

This is actual Linux LlamaEngine inference with unchanged reviewed reducer policy
and a synthetic SQLite executor. Actual production search/read/source-policy
functions are additionally covered by the Swift tests. It is not an exercised
iOS LocalAgentSession/UI flow. The follow-up source only removes a redundant
same-type provider cast and adds evidence/docs; engine and model-test source
remain unchanged from the tested commit.

Once the application build explicitly enables ORIVYN_NATIVE_TRANSCRIPT and passes
its Apple/UI gates, the existing user-facing path is:
1. In Models, manually install/select Qwen 3 · 1.7B · Q4_K_M (catalog ID
   qwen3-1.7b-q4_k_m, 1,282,439,264 bytes). The catalog already ships this entry.
2. Open Local tasks, choose Read messages, and enter an exact quoted conversation
   title and one message number, for example Read message 2 of "Project notes".
3. Draft plan, check that Search and Conversation title are identical and that
   the requested message number is correct, then Approve and create task.
4. Tap Run. Approval alone does not start a read.

This uses the selected installed LocalAIProvider and existing LocalModelStore,
not a separate tool-model installation. No model is downloaded automatically by
this route. Other models and unsupported plans retain the existing reviewed path.
Allow approximately 1.3 GB additional temporary disk space for the private model
snapshot; release and ordinary failure/cancellation cleanup were tested. Physical
device memory/storage behavior and crash-orphan cleanup remain unverified.
