# Native transcript and engine development evidence

This is an experimental bounded local read workflow, not general autonomous tool use.
No AppModel or LocalAgentSession caller uses this route. The production app does not
define ORIVYN_NATIVE_TRANSCRIPT.

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
