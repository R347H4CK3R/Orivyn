# Simulator text CPU scheduling hypothesis

The simulator-only text-engine context now uses `max(1, min(2, activeProcessorCount))` threads for both prompt processing and generation. The previous `max(1, min(4, activeProcessorCount - 2))` formula uses only one thread on a three-core GitHub-hosted Mac. Physical iPhone/device policy retains the previous formula. Simulator GPU offload remains disabled. No model, model-size cap, context size, token bound, generation deadline, assertion, fallback or approval behavior changes.

This is a bounded performance hypothesis requiring a new Mac simulator run, not a proven fix or device performance claim. Prior sequential Linux probes with the real Qwen3 1.7B model took 27.149 seconds with one thread and 28.592 seconds with two; they did not demonstrate a speedup and cannot establish ARM simulator behavior.

## Evidence motivating a simulator experiment

- Full-suite source 4ce8001: the automatic general-model turn returned “The capital of France is Paris.” by approximately 55 seconds. The coder request was sent at 64 seconds; its 210-second response wait expired with `Automatic: Qwen 2.5 Coder · 1.5B · Q4_K_M · Coding`, an empty composer, `composer.stop`, and the “Generating response” spinner visible. There was no preparation panel or error alert. Preparation/download/verification had reached submission, but no response content had reached the UI by the deadline. Evidence: `AutomaticRealInferenceUITests`, exported hierarchy `2F926B13-2790-43B3-8A98-61AAF0A24403.txt` in full artifact SHA-256 `ec30f89134e94fe7c697198b711e7a6f3eca51e0c4530a9de1a6efc9e84ddac9`.
- The separate real native-tools simulator run failed after 104.142 seconds with the old undifferentiated `invalidState`. Its typed-status follow-up is independent evidence still required to identify the failure. The original failure does not prove timeout. Host VM evidence also showed compression and swapping on a 7 GiB Mac, so CPU scheduling is not the only possible factor.

## Ownership/stream review

Automatic preparation creates providers with the same `AppModel.localEngine`, not one engine per selected model. The engine rejects overlapping requests using `busy` and release admission. A changed model path clears its prior resource owner before loading the replacement. `LlamaResources.deinit` frees context before model. Native text generation retains its owner while running and unload waits for the owned worker. The old automatic ticket is cleared before synchronous submission; stale progress callbacks fail the ownership check. No clear deadlock or retained second-model defect was identified in this review. File hashing and native model loading are synchronous phases, and decode yields only at batch/token boundaries; the evidence does not pinpoint which of these stalled.

Validation for this source change is syntax/branch review only. Re-run the unchanged actual automatic general/coder quality assertions and the real native-tools suggestion/reload gate on the authorized Mac runner before claiming improvement.
