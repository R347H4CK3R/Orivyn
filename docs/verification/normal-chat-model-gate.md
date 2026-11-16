# Required real-model normal-chat loop gate

`ProductionNormalChatLocalAgentTests` contains two opt-in tests. No test downloads models or injects a model decision. Use the existing combined native gate, serially with the other pinned-model tests; do not run a second competing fixture job.

Required TestAction environment:
- `ORIVYN_REQUIRE_NORMAL_CHAT_MODEL=1`
- `ORIVYN_PRODUCTION_MODEL_ID=qwen3-1.7b-q4_k_m`
- `ORIVYN_CONVERSATION_MODEL_DIR=<existing dedicated directory containing verified Q4 file>`

Add `-only-testing:JarvisEVOTests/ProductionNormalChatLocalAgentTests` and increment required test count by two. Missing opt-in skips and must fail the required zero-skip gate. Provider-test allowance is 600 seconds; Automatic-test allowance is 480 seconds. Reuses the production fixture lock and independent descriptor pin.

1. **Provider loop:** actual LocalAIProvider decisions select a tool; the real LocalReadTools dispatcher reads synthetic SQLite-backed memory. The test recorder synchronizes receipts to disk before returning and checks started-before-dispatch and success-before-next-inference. A random marker exists only in memory, not initial model inputs. Require a real successful memory-search receipt, the marker in subsequent model input, and the marker in the generated answer. The wrapper observes model requests, never modifies outputs. Provider deadline is explicitly 360 seconds for the memory diagnostic; production limits are unchanged. A fresh coding turn then uses the production default deadline and must produce a Python print statement with exactly one actual-model request and zero reads/receipts.
2. **Automatic route:** real AppModel Send, default Automatic preparer, router and provider factory, with exactly the pinned model installed. The natural request must not match deterministic shortcuts. Require selection of pinned installed model without download, actual persisted search receipt, completed SQLite conversation and unpredictable marker in final model answer separately from receipt text. No preparer or model factory is injected. This tests native application logic, not physical UI interactions.

Only synthetic memories/prompts/results are attached. No user data, model secrets or raw reasoning is uploaded. The Automatic test restores prior fixture-manifest bytes after joined cleanup; timed-out work that fails to join retains its fixture state rather than deleting live evidence.

Current status: test source syntax checked only. Native type checking, pinned-model decisions and physical iPhone behavior are unverified until execution. Passing these two cases would not prove general autonomous workflows, plugins, writes or arbitrary tools.
