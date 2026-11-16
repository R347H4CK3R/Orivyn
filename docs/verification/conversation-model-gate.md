# Pinned conversational semantic gate integration

Add `ProductionConversationResponseTests` to the existing combined simulator run, not a separate CI dispatch. It is one required test with three sequential fixed synthetic prompts. It uses the pinned Qwen3 1.7B Q4 model through LocalAIProvider, including file-size/SHA verification and the production prompt plus output filter. It does not mock inference, inject replies, execute generated Python, retry a failed prompt, or inspect private user data.

The gate checks one Python function, one direct factual reply in thinking-enabled mode, and one supported-capability inventory/limit response. Passing these probes does not guarantee all conversational behavior or arbitrary reasoning quality. AppModel persistence/visibility is checked separately by native integration tests. Human review of visible-answer xcresult attachments remains useful.

Before xcodebuild:

```bash
MODEL_DIR="$RUNNER_TEMP/orivyn-conversation-model"
mkdir -p "$MODEL_DIR"
python3 Diagnostics/NativeTools/download.py --model-id qwen3-1.7b-q4_k_m --output "$MODEL_DIR/Qwen3-1.7B-Q4_K_M.gguf"
```

Pass these variables to the simulator test runner through the generated scheme's TestAction EnvironmentVariables (not only shell exports; verify required gate did not skip):

- `ORIVYN_REQUIRE_CONVERSATION_MODEL=1`
- `ORIVYN_PRODUCTION_MODEL_ID=qwen3-1.7b-q4_k_m`
- `ORIVYN_CONVERSATION_MODEL_DIR=<absolute MODEL_DIR>`

Add `-only-testing:JarvisEVOTests/ProductionConversationResponseTests`, allow this test 600 seconds, disable parallel execution, and increment required total count by one. Policy inventory adds one deterministic test to ChatResponsePolicyTests too. A missing flag skips, which the required zero-skips summary check must fail. Missing/wrong bytes or wrong descriptor fail, never silently use another model. The test takes the existing production-fixture lock and never alters a model manifest. Attachments record only synthetic visible answers, prompt, and pinned hash, not raw reasoning.
