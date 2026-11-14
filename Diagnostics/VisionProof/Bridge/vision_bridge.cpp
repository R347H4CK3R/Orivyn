#include "vision_bridge.h"
#include "llama.h"
#include "mtmd.h"
#include "mtmd-helper.h"
#include <atomic>
#include <algorithm>
#include <mutex>
#include <memory>
#include <string>
#include <vector>
#include <cstring>
#include <cctype>
#include <stdexcept>
#include <thread>
#include <chrono>
struct ov_session {std::atomic<bool> cancel{false};std::mutex execution;std::atomic<int> phase{0};std::atomic<int> callbacks{0};
#ifdef OV_TESTING
 std::atomic<int> cancel_phase{-1};std::atomic<int> hold_phase{-1};
#endif
};
static std::mutex engine_slot;
static std::once_flag backend_once;
static std::once_flag vision_log_once;
// mtmd and clip share a process-global logger which can print user prompt text.
// Configure it before the first owned session and keep it for process lifetime:
// restoring/toggling it per request would race with other vision callbacks.
// This bridge owns the app's mtmd entrypoints. Do not change llama/ggml logging.
static void discard_vision_log(ggml_log_level, const char *, void *) {}
static std::atomic<int> live{0};
template<class T,void(*F)(T*)> struct Owner {
 T *p; explicit Owner(T *v):p(v){if(p)++live;} ~Owner(){if(p){F(p);--live;}}
 Owner(const Owner&)=delete;Owner&operator=(const Owner&)=delete;
};
static void check(ov_session *s){if(s->cancel.load())throw 2;}
static bool canceled(ov_session*s){
#ifdef OV_TESTING
 while(s->phase.load()==s->hold_phase.load()&&!s->cancel.load())std::this_thread::sleep_for(std::chrono::milliseconds(1));
 if(s->phase.load()==s->cancel_phase.load())s->cancel.store(true);
#endif
 return s->cancel.load();
}
static bool load_progress(float,void*p){auto*s=static_cast<ov_session*>(p);++s->callbacks;return !canceled(s);}
static bool abort_decode(void*p){auto*s=static_cast<ov_session*>(p);++s->callbacks;return canceled(s);}
static bool eval_callback(ggml_tensor*,bool ask,void*p){
 // ask=true requests node observation; false here would NOT request abort.
 if(ask)return true;
 auto*s=static_cast<ov_session*>(p);++s->callbacks;return !canceled(s);
}
static bool utf8(const std::string&s){
 size_t i=0;while(i<s.size()){uint8_t c=s[i++];if(c<128){if(c==0)return false;continue;}
 unsigned n=0;uint32_t v=0,min=0;
 if(c>=0xc2&&c<=0xdf){n=1;v=c&31;min=128;}else if(c>=0xe0&&c<=0xef){n=2;v=c&15;min=2048;}
 else if(c>=0xf0&&c<=0xf4){n=3;v=c&7;min=65536;}else return false;
 if(i+n>s.size())return false;while(n--){uint8_t b=s[i++];if((b&192)!=128)return false;v=(v<<6)|(b&63);}
 if(v<min||v>0x10ffff||(v>=0xd800&&v<=0xdfff))return false;
 }return true;
}
static void validate(const ov_request&r,size_t cap){
 if(!r.model||!r.projector||!r.rgb||!r.question||r.width<1||r.height<1||r.width>512||r.height>512||
 r.rgb_bytes!=size_t(r.width)*r.height*3||r.context!=2048||r.output_tokens<1||r.output_tokens>128||
 r.question_bytes<1||r.question_bytes>4096||cap<2||cap>65536)throw 1;
 std::string q(r.question,r.question_bytes);
 if(!utf8(q)||q.find(mtmd_default_marker())!=std::string::npos||q.find("<|im_")!=std::string::npos)throw 1;
 bool visible=false;for(unsigned char c:q)if(!std::isspace(c))visible=true;if(!visible)throw 1;
 // Pixel-only abstention: flat color and <=2/255 codec noise contain no
 // discernible detail. Never synthesize model descriptions for these inputs.
 uint8_t lo[3]={255,255,255},hi[3]={0,0,0};bool detail=false;
 for(size_t i=0;i<r.rgb_bytes;++i){auto c=i%3;lo[c]=std::min(lo[c],r.rgb[i]);hi[c]=std::max(hi[c],r.rgb[i]);
  if(int(hi[c])-int(lo[c])>2){detail=true;break;}}
 if(!detail)throw 10;
}
static void generate(ov_session*s,const ov_request&r,std::string&out,ov_report&report,size_t cap){
 check(s);s->phase=1;
 std::call_once(backend_once,[]{llama_backend_init();});
 auto mp=llama_model_default_params();mp.n_gpu_layers=0;mp.use_mmap=true;
 mp.progress_callback=load_progress;mp.progress_callback_user_data=s;
 Owner<llama_model,llama_model_free> model(llama_model_load_from_file(r.model,mp));check(s);if(!model.p)throw 3;
 auto cp=llama_context_default_params();cp.n_ctx=2048;cp.n_batch=128;cp.n_ubatch=128;cp.n_threads=2;cp.n_threads_batch=2;
 cp.offload_kqv=false;cp.abort_callback=abort_decode;cp.abort_callback_data=s;
 Owner<llama_context,llama_free> ctx(llama_init_from_model(model.p,cp));if(!ctx.p)throw 3;check(s);
 s->phase=2;auto vp=mtmd_context_params_default();vp.use_gpu=false;vp.n_threads=2;vp.warmup=false;vp.cb_eval=eval_callback;vp.cb_eval_user_data=s;
 Owner<mtmd_context,mtmd_free> vision(mtmd_init_from_file(r.projector,model.p,vp));if(!vision.p||!mtmd_support_vision(vision.p))throw 3;check(s);
 Owner<mtmd_bitmap,mtmd_bitmap_free> bitmap(mtmd_bitmap_init(r.width,r.height,r.rgb));if(!bitmap.p)throw 4;
 Owner<mtmd_input_chunks,mtmd_input_chunks_free> chunks(mtmd_input_chunks_init());if(!chunks.p)throw 4;
 std::string text=std::string(mtmd_default_marker())+"\n"+std::string(r.question,r.question_bytes);
 llama_chat_message msg{"user",text.c_str()};const char*templ=llama_model_chat_template(model.p,nullptr);if(!templ)throw 4;
 int n=llama_chat_apply_template(templ,&msg,1,true,nullptr,0);if(n<=0||n>16384)throw 4;
 std::vector<char> prompt(n+1);if(llama_chat_apply_template(templ,&msg,1,true,prompt.data(),prompt.size())!=n)throw 4;
 prompt[n]=0;mtmd_input_text input{prompt.data(),true,true};const mtmd_bitmap *images[]={bitmap.p};
 if(mtmd_tokenize(vision.p,chunks.p,&input,images,1)!=0)throw 4;check(s);
 // Some older converted vocabularies lack special tokens required by this pinned
 // mtmd preprocessor. Reject its sentinel tokens before any decode is dispatched.
 const auto *prepared_vocab=llama_model_get_vocab(model.p);
 if(!prepared_vocab)throw 4;
 const auto vocabulary_size=llama_vocab_n_tokens(prepared_vocab);
 for(size_t i=0;i<mtmd_input_chunks_size(chunks.p);++i){
  const auto *chunk=mtmd_input_chunks_get(chunks.p,i);
  if(mtmd_input_chunk_get_type(chunk)!=MTMD_INPUT_CHUNK_TYPE_TEXT)continue;
  size_t count=0;const auto *ids=mtmd_input_chunk_get_tokens_text(chunk,&count);
  if(count&&!ids)throw 4;
  for(size_t j=0;j<count;++j)if(ids[j]<0||ids[j]>=vocabulary_size)throw 4;
 }

 auto positions=mtmd_helper_get_n_pos(chunks.p);auto tokens=mtmd_helper_get_n_tokens(chunks.p);
 if(positions<=0||tokens==0||positions+int(r.output_tokens)>2048||tokens+r.output_tokens>2048)throw 5;
 report.positions=positions;
 for(size_t i=0;i<mtmd_input_chunks_size(chunks.p);++i)if(mtmd_input_chunk_get_type(mtmd_input_chunks_get(chunks.p,i))==MTMD_INPUT_CHUNK_TYPE_IMAGE)++report.image_chunks;
 if(report.image_chunks!=1)throw 4;
 llama_pos past=0;
 for(size_t i=0;i<mtmd_input_chunks_size(chunks.p);++i){
  check(s);const auto*chunk=mtmd_input_chunks_get(chunks.p,i);
  s->phase=mtmd_input_chunk_get_type(chunk)==MTMD_INPUT_CHUNK_TYPE_IMAGE?3:4;
  int rc=mtmd_helper_eval_chunk_single(vision.p,ctx.p,chunk,past,0,128,i+1==mtmd_input_chunks_size(chunks.p),&past);
  check(s);if(rc||past<0||past>2048)throw 6;
 }
 Owner<llama_sampler,llama_sampler_free> sampler(llama_sampler_init_greedy());if(!sampler.p)throw 3;
 const auto*vocab=llama_model_get_vocab(model.p);if(!vocab)throw 3;
 for(uint32_t i=0;i<r.output_tokens;++i){
  check(s);s->phase=5;auto token=llama_sampler_sample(sampler.p,ctx.p,-1);if(llama_vocab_is_eog(vocab,token))break;
  char piece[256];int count=llama_token_to_piece(vocab,token,piece,sizeof(piece),0,false);
  if(count<0||out.size()+size_t(count)>=cap)throw 8;
  out.append(piece,count);++report.tokens;
  // No EOG was observed: never report a token-truncated answer as complete.
  if(i+1==r.output_tokens)throw 8;
  auto batch=llama_batch_get_one(&token,1);int rc=llama_decode(ctx.p,batch);check(s);if(rc)throw 6;
 }
 check(s);
}
extern "C" ov_session*ov_create(void){try{
 std::call_once(vision_log_once,[]{mtmd_log_set(discard_vision_log,nullptr);});
 return new ov_session;
}catch(...){return nullptr;}}
extern "C" void ov_cancel(ov_session*s){if(s)s->cancel=true;}
extern "C" void ov_destroy(ov_session*s){if(!s)return;ov_cancel(s);{std::lock_guard<std::mutex>wait(s->execution);}delete s;}
extern "C" int ov_run(ov_session*s,const ov_request*r,char*out,size_t cap,ov_report*report){
 if(!s||!r||!out||!report)return 1;*report={};if(cap)out[0]=0;
 std::unique_lock<std::mutex>own(s->execution,std::try_to_lock);if(!own.owns_lock()){report->status=7;return 7;}
 std::unique_lock<std::mutex>slot(engine_slot,std::try_to_lock);if(!slot.owns_lock()){report->status=7;return 7;}
 int status=0;std::string result;
 try{validate(*r,cap);generate(s,*r,result,*report,cap);}catch(int code){status=code;}catch(...){status=9;}
 report->status=status;report->phase=s->phase;report->callback_count=s->callbacks;report->live_resources=live;
 if(status==0){memcpy(out,result.data(),result.size());out[result.size()]=0;}return status;
}
#ifdef OV_TESTING
extern "C" void ov_test_cancel_at(ov_session*s,int phase){s->cancel_phase=phase;}
extern "C" void ov_test_hold_at(ov_session*s,int phase){s->hold_phase=phase;}
extern "C" int ov_test_phase(ov_session*s){return s->phase;}
extern "C" int ov_live_resources(void){return live;}
#endif
