# Native generation failure diagnostics

The real iOS simulator gate on source ed914a5 failed after 104.142 seconds with `invalidState`. That old status did not distinguish native expiry, decoding, prompt/context admission or completion validation. The C reservation schema matches the Swift decoder. The log alone does not establish the root cause; the 60-second native deadline is a hypothesis, not a confirmed diagnosis.

`ov3_generate` now returns documented stable failure codes. Swift preserves the code and monotonic elapsed duration as `LocalAgentError.nativeGenerationFailed`. No prompt, output text, model path or private content is logged. Successful output and all schema/permission, cancellation, deadline, token, byte and context limits are unchanged. TTL remains 60 seconds. Any nonzero result still produces no proposal.

Validated on Linux with the actual pinned 1.7B model: eight lifecycle scenarios, four creation boundaries, three real goal probes, all 24 parser/ownership boundary regressions, and the exact production Swift actor's native generation/cancellation/unload/reload/chat checks. Explicit status assertions cover cancellation, expiry, invalid arguments, occupied context, token limit and one-shot reuse. The adversarial completion returns status 10 with null output. A new Apple run is required to diagnose its prior opaque failure.
