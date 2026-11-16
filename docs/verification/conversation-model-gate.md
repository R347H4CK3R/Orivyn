# Pinned conversational semantic gate integration

Add `ProductionConversationResponseTests` to the existing combined simulator run, not a separate CI dispatch. It is one required test with four sequential fixed synthetic prompts. It uses the pinned Qwen3 1.7B Q4 model through LocalAIProvider, including file-size/SHA verification and the production prompt plus output filter. It does not mock inference, inject replies, execute generated Python, retry a failed prompt, or inspect private user data.

The gate checks one Python function, one direct factual reply in thinking-enabled mode, one supported-capability inventory/limit response, and a separate plugin-approval response. Passing these probes does not guarantee all conversational behavior or arbitrary reasoning quality. AppModel persistence/visibility is checked separately by native integration tests. Human review of visible-answer xcresult attachments remains useful.

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

Add `-only-testing:JarvisEVOTests/ProductionConversationResponseTests`, allow this test 750 seconds, disable parallel execution, and increment required total count by one. Policy inventory adds one deterministic test to ChatResponsePolicyTests too. A missing flag skips, which the required zero-skips summary check must fail. Missing/wrong bytes or wrong descriptor fail, never silently use another model. The test takes the existing production-fixture lock and never alters a model manifest. Attachments record only synthetic visible answers, prompt, and pinned hash, not raw reasoning.

## Inventory failure and repair candidate

Run 43816635355 returned valid Python square code and a direct Paris answer, but its inventory response invented device/user information and local filesystem access instead of app information and memory search. The gate correctly failed; it was not a three-probe pass. It also failed to describe reviewed actions. Assertions remain intact.

The repair candidate supplies an explicitly exhaustive, named inventory through `DirectChatRead`, with parity tests against the typed-request parser. It excludes invented filesystem/device access and removes stale repository-visibility labels without granting source access. The synthetic model gate now attaches its exact system policy to help verify the input boundary. No private user data is used.

Candidate verification: 533 exact-source Foundation tests pass, including the two new inventory regressions. Required actual-model rerun is outstanding; do not claim capability hallucination is fixed yet. Existing unrelated Python suite failures/errors remain documented in the response-boundary report; the stale repository-visibility assertion was updated and its two-file-manifest tests pass.

## Explicit plugin-approval probe correction

Run 43821742941 passed 124 of 125 native checks. The remaining conversational test returned the exact three supported reads and explicitly denied automatic email/build/publication, but omitted plugin review. Its third prompt asked about local reads and email/build limitations, not connected plugins; nevertheless its oracle required the word “review.” This was an underspecified probe. The run remains failed, not retroactively passed.

The original third synthetic prompt and its inventory/denial assertions remain unchanged. A separate fourth prompt explicitly asks what approval a connected plugin call needs and whether it can run without reviewing the exact call. The misplaced review assertion moves to that probe, strengthened to require exact-call precision and required review before execution, with its own visible-answer evidence. Python, no-echo, reasoning-boundary, inventory and denial checks remain. No production behavior changed, and there are no retries. The actual-model rerun is pending; no claim of 125/125 is made. Allow the four-probe test up to 750 seconds; each individual model request remains bounded to 150 seconds.

The plugin-approval oracle is lexical, not a complete semantic guarantee. Review its retained actual visible-answer attachment manually alongside the result. Two deterministic fixture tests cover required exact-call approval and contradictory no-review claims; include ConversationApprovalOracleTests in the native gate (two additional tests).
