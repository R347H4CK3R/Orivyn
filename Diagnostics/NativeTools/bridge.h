#pragma once
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
struct llama_model;
struct llama_context;
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
