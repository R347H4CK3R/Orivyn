#include "bridge.h"
#include "llama.h"
#include "chat.h"
#include "sampling.h"
#include "common.h"
#include "pinned-template.h"
#include <nlohmann/json.hpp>
#include <chrono>
#include <memory>
#include <mutex>
#include <set>
#include <stdexcept>
#include <cstring>
#include <cstdlib>
#include <atomic>
using J=nlohmann::ordered_json;
namespace {
struct Session {
 llama_model *model=nullptr;
 common_chat_params chat;
 std::atomic<bool> attempted{false};
 common_chat_templates_ptr templates;
 common_chat_parser_params parser;
 unsigned approved=0,used=0,budget=0,count=0;
 std::atomic<bool> cancelled{false};
 std::chrono::steady_clock::time_point deadline;
 std::mutex mutex;
 ~Session(){templates.reset();}
};
void require(bool yes){if(!yes)throw std::runtime_error("rejected");}
char* copy(const std::string&s){require(s.size()<4096);auto*p=(char*)malloc(s.size()+1);if(!p)throw std::bad_alloc();memcpy(p,s.data(),s.size());p[s.size()]=0;return p;}
void whitespace(const std::string&s,size_t&i){while(i<s.size()&&(s[i]==' '||s[i]=='\n'||s[i]=='\r'||s[i]=='\t'))++i;}
void literal(const std::string&s,size_t&i,const std::string&v){require(s.compare(i,v.size(),v)==0);i+=v.size();}
J strict_json(const std::string&s){
 std::vector<std::set<std::string>> keys;
 auto cb=[&](int depth,J::parse_event_t e,J& value){require(depth<=4);if(e==J::parse_event_t::object_start)keys.emplace_back();if(e==J::parse_event_t::key){require(!keys.empty());require(keys.back().insert(value.get<std::string>()).second);}if(e==J::parse_event_t::object_end){require(!keys.empty());keys.pop_back();}return true;};
 return J::parse(s,cb,true,false);
}
std::vector<std::string> checked_envelopes(const std::string&s){
 size_t i=0;std::vector<std::string> names;whitespace(s,i);
 // Only the exact known empty non-thinking prefix is accepted; arbitrary reasoning is not executable input.
 const std::string pre="<think>\n\n</think>\n\n";if(s.compare(i,pre.size(),pre)==0)i+=pre.size();whitespace(s,i);
 while(i<s.size()){
  require(names.size()<2);literal(s,i,"<tool_call>");whitespace(s,i);require(i<s.size()&&s[i]=='{');size_t start=i;int depth=0;bool quoted=false,escape=false;
  for(;i<s.size();++i){char c=s[i];if(quoted){if(escape)escape=false;else if(c=='\\')escape=true;else if(c=='"')quoted=false;continue;}if(c=='"'){quoted=true;continue;}if(c=='{'||c=='['){++depth;require(depth<=4);}if(c=='}'||c==']'){--depth;require(depth>=0);if(depth==0){++i;break;}}}
  require(depth==0&&!quoted&&!escape);auto obj=strict_json(s.substr(start,i-start));
  require(obj.is_object()&&obj.size()==2&&obj.contains("name")&&obj.contains("arguments"));require(obj["name"].is_string()&&obj["arguments"].is_object()&&obj["arguments"].empty());
  names.push_back(obj["name"].get<std::string>());whitespace(s,i);literal(s,i,"</tool_call>");whitespace(s,i);
 }
 require(!names.empty());return names;
}
}
static int create_session(llama_model* model,unsigned approved,unsigned budget,unsigned ttl,const std::string&goal,void**out){
 const auto started=std::chrono::steady_clock::now();
 if(!out)return 1;*out=nullptr;
 try{
  require(model&&approved&&!(approved&~3u)&&budget>0&&budget<=2&&ttl>0&&ttl<=60000);
  const char* supplied=llama_model_chat_template(model,nullptr);require(supplied);
  const size_t length=strnlen(supplied,8193);require(length==sizeof(kPinnedQwen3Template)-1&&length<=8192&&memcmp(supplied,kPinnedQwen3Template,length)==0);
  char architecture[32]={0};int n=llama_model_meta_val_str(model,"general.architecture",architecture,sizeof(architecture));require(n==5&&memcmp(architecture,"qwen3",5)==0);
  auto p=std::make_unique<Session>();p->deadline=started+std::chrono::milliseconds(ttl);
  p->templates=common_chat_templates_init(model,kPinnedQwen3Template);
  common_chat_templates_inputs in;in.enable_thinking=false;in.parallel_tool_calls=true;common_chat_msg m;m.role="user";m.content=goal;in.messages.push_back(m);
  if(approved&1)in.tools.push_back({"get_app_info","Application identity",R"({"type":"object","properties":{},"additionalProperties":false})"});
  if(approved&2)in.tools.push_back({"list_models","Installed models",R"({"type":"object","properties":{},"additionalProperties":false})"});
  auto cp=common_chat_templates_apply(p->templates.get(),in);
  require(cp.format==COMMON_CHAT_FORMAT_PEG_NATIVE&&!cp.parser.empty()&&cp.parser.size()<=32768&&cp.prompt.size()<=16384&&cp.grammar.size()<=8192);
  p->model=model;p->chat=cp;
  p->parser=common_chat_parser_params(cp);p->parser.parser.load(cp.parser);
  require(std::chrono::steady_clock::now()<p->deadline);p->approved=approved;p->budget=budget;*out=p.release();return 0;
 }catch(...){return 1;}
}
extern "C" int ov2_create_borrowed(llama_model*m,unsigned a,unsigned b,unsigned t,void**out){return create_session(m,a,b,t,"Read the reviewed application identity and installed models.",out);}
extern "C" int ov3_create_borrowed(llama_model*m,unsigned a,unsigned b,unsigned t,const char*goal,size_t length,void**out){
 if(!out)return 1;*out=nullptr;
 if(!goal||length==0||length>2048||memchr(goal,0,length))return 1;
 try{return create_session(m,a,b,t,std::string(goal,length),out);}catch(...){return 1;}
}
extern "C" int ov2_validate(void*handle,const char*bytes,size_t length,int eog,char**out){
 if(!out){return 1;}
 *out=nullptr;
 try{require(handle&&bytes&&length>0&&length<=65536&&eog==1);auto&s=*(Session*)handle;std::lock_guard<std::mutex>l(s.mutex);require(!s.cancelled&&std::chrono::steady_clock::now()<s.deadline);
 std::string raw(bytes,length);require(raw.find('\0')==std::string::npos);auto names=checked_envelopes(raw);unsigned proposed=0;
 require(s.count+names.size()<=s.budget);for(auto&n:names){unsigned bit=n=="get_app_info"?1:n=="list_models"?2:0;require(bit&&(s.approved&bit)&&!(s.used&bit)&&!(proposed&bit));proposed|=bit;}
 // Strict upstream PEG is an additional syntax gate; the independent scanner/schema remains authoritative.
 std::string effective=s.parser.generation_prompt+raw;common_peg_parse_context context(effective,COMMON_PEG_PARSE_FLAG_NONE);auto parsed=s.parser.parser.parse(context);bool partial=false;context.ast.visit(parsed,[&](const common_peg_ast_node&n){partial=partial||n.is_partial;});require(parsed.success()&&!parsed.need_more_input()&&!partial&&parsed.end==effective.size());
 auto mapped=common_chat_parse(raw,false,s.parser);require(mapped.tool_calls.size()==names.size());for(size_t i=0;i<names.size();++i){require(mapped.tool_calls[i].name==names[i]&&strict_json(mapped.tool_calls[i].arguments)==J::object());}
 require(!s.cancelled&&std::chrono::steady_clock::now()<s.deadline);J result={{"state","reserved_not_executed"},{"reserved_reads",J::array()}};for(size_t i=0;i<names.size();++i)result["reserved_reads"].push_back({{"name",names[i]},{"arguments",J::object()},{"session_sequence",s.count+i+1}});
 auto*buffer=copy(result.dump());s.used|=proposed;s.count+=names.size();*out=buffer;return 0;
 }catch(...){return 1;}
}
extern "C" void ov2_cancel(void*h){if(h)((Session*)h)->cancelled=true;}
extern "C" void ov2_destroy(void*h){try{delete (Session*)h;}catch(...){}}
extern "C" void ov2_free(char*p){free(p);}

// Exclusive borrowed context: caller serializes all use and keeps model/context alive.
// Only an empty context is accepted; no user conversation cache is erased.
// Context is cleared on every exit after admission; caller must not reuse stale logits.
extern "C" int ov3_generate(void*handle,llama_context*ctx,unsigned max_tokens,char**out){
 if(!out)return 1;*out=nullptr;
 if(!handle||!ctx)return 1;
 auto&s=*(Session*)handle;
 if(s.attempted.exchange(true))return 1;
 struct Cleanup {Session&s;llama_context*ctx=nullptr;~Cleanup(){s.cancelled=true;if(ctx)llama_memory_clear(llama_get_memory(ctx),true);}} cleanup{s};
 try{
  auto alive=[&](){require(!s.cancelled&&std::chrono::steady_clock::now()<s.deadline);};
  alive();require(max_tokens>0&&max_tokens<=512&&llama_get_model(ctx)==s.model);
  auto mem=llama_get_memory(ctx);require(mem&&llama_n_seq_max(ctx)==1&&llama_memory_seq_pos_max(mem,0)<0);
  cleanup.ctx=ctx;
  auto tokens=common_tokenize(ctx,s.chat.prompt,true,true);
  require(!tokens.empty()&&tokens.size()+max_tokens<=llama_n_ctx(ctx));
  common_params_sampling sp;sp.temp=0.0;sp.seed=42;
  sp.grammar=common_grammar(COMMON_GRAMMAR_TYPE_TOOL_CALLS,s.chat.grammar);
  sp.grammar_lazy=s.chat.grammar_lazy;sp.grammar_triggers=s.chat.grammar_triggers;
  for(const auto &word:s.chat.preserved_tokens){auto ids=common_tokenize(ctx,word,false,true);require(ids.size()==1);sp.preserved_tokens.insert(ids[0]);}
  std::unique_ptr<common_sampler,decltype(&common_sampler_free)> sampler(common_sampler_init(s.model,sp),common_sampler_free);require(bool(sampler));
  for(size_t i=0;i<tokens.size();){alive();size_t n=std::min<size_t>(llama_n_batch(ctx),tokens.size()-i);require(n>0);auto batch=llama_batch_get_one(tokens.data()+i,n);require(llama_decode(ctx,batch)==0);i+=n;alive();}
  std::string raw;const auto*vocab=llama_model_get_vocab(s.model);
  for(unsigned i=0;i<max_tokens;++i){
   alive();auto t=common_sampler_sample(sampler.get(),ctx,-1);common_sampler_accept(sampler.get(),t,true);
   if(llama_vocab_is_eog(vocab,t)){alive();return ov2_validate(handle,raw.data(),raw.size(),1,out);}
   raw+=common_token_to_piece(ctx,t,true);require(raw.size()<=65536);
   // Template-specific stops are only accepted on an exact suffix, never truncation.
   for(const auto&stop:s.chat.additional_stops)if(!stop.empty()&&raw.size()>=stop.size()&&raw.compare(raw.size()-stop.size(),stop.size(),stop)==0){raw.resize(raw.size()-stop.size());alive();return ov2_validate(handle,raw.data(),raw.size(),1,out);}
   auto batch=llama_batch_get_one(&t,1);require(llama_decode(ctx,batch)==0);alive();
  }
  return 1; // Token limit is incomplete, never an executable/reservable prefix.
 }catch(...){return 1;}
}
