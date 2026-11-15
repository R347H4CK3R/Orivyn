#pragma once
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
struct llama_model;
struct llama_context;
// Stable ov3_generate outcomes. Nonzero always returns no reservation/output.
// No model text, file paths, prompts or private content are exposed by diagnostics.
enum ov3_generation_status {
 OV3_SUCCESS=0, OV3_INVALID_ARGUMENT=1, OV3_CANCELLED=2, OV3_EXPIRED=3,
 OV3_CONTEXT_REJECTED=4, OV3_PROMPT_LIMIT=5, OV3_SAMPLER_FAILED=6,
 OV3_DECODE_FAILED=7, OV3_OUTPUT_LIMIT=8, OV3_TOKEN_LIMIT=9,
 OV3_COMPLETION_REJECTED=10, OV3_INTERNAL_ERROR=11, OV3_ALREADY_ATTEMPTED=12
};
// Model policy is selected by a trusted owner after SHA-256 file verification.
// Exact model template must match this policy; unknown IDs never fall back.
// Legacy ov2/ov3 creation remains policy 1 only. Policy 2 is a review candidate.
enum ov4_model_policy { OV4_POLICY_Q8=1, OV4_POLICY_Q4_CANDIDATE=2 };
int ov4_create_borrowed(struct llama_model*, unsigned policy, unsigned approved_mask, unsigned call_budget, unsigned ttl_ms, const char *goal, size_t goal_length, void **out);
// Bounded caller goal, offered tools restricted to reviewed mask; no execution.
int ov3_create_borrowed(struct llama_model*, unsigned approved_mask, unsigned call_budget, unsigned ttl_ms, const char *goal, size_t goal_length, void **out);
// One-shot synchronous generation. Requires exclusive, initially empty context.
// Caller retains both resources until return; cancel may be called concurrently.
// destroy must wait for return. Cooperative deadline checks surround decode.
int ov3_generate(void *handle, struct llama_context *context, unsigned max_tokens, char **out_json);
// Only a model retained by the trusted engine owner may be borrowed. Caller must keep
// model alive until all calls finish and ov2_destroy returns. No path or credential API.
// TTL includes template setup; expiry is detected, synchronous setup is not preempted.
int ov2_create_borrowed(struct llama_model *model, unsigned approved_mask, unsigned call_budget, unsigned ttl_ms, void **out);
int ov2_validate(void *handle, const char *bytes, size_t length, int ended_normally, char **out_json);
void ov2_cancel(void *handle);
void ov2_destroy(void *handle);
void ov2_free(char *buffer);
#ifdef __cplusplus
}
#endif
