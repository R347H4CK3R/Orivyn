#ifndef ORIVYN_VISION_BRIDGE_H
#define ORIVYN_VISION_BRIDGE_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Private worker ABI: Swift UI must never receive this opaque handle. Caller
   keeps request buffers alive through synchronous run. No call may begin after
   destroy starts; cancel may run concurrently with run; destroy waits for run. */
typedef struct ov_session ov_session;
typedef struct {const char *model,*projector;const uint8_t *rgb;size_t rgb_bytes;
 uint32_t width,height;const char *question;size_t question_bytes;uint32_t context,output_tokens;} ov_request;
typedef struct {int status,phase,tokens,positions,image_chunks,callback_count,live_resources;} ov_report;
/* 0 success, 1 invalid, 2 cancelled, 3 load, 4 tokenize/template,
   5 context budget, 6 evaluation, 7 busy, 8 output byte/token limit (partial output discarded), 9 internal,
   10 no discernible visual detail (pixel-only abstention, no model load). */
ov_session *ov_create(void);
void ov_cancel(ov_session *);
void ov_destroy(ov_session *);
int ov_run(ov_session *,const ov_request *,char *output,size_t capacity,ov_report *);
#ifdef OV_TESTING
void ov_test_cancel_at(ov_session *,int phase);
void ov_test_hold_at(ov_session *,int phase);
int ov_test_phase(ov_session *);
int ov_live_resources(void);
#endif
#ifdef __cplusplus
}
#endif
#endif
