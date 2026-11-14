#include "bridge.h"
#include "llama.h"
#include <map>
#include <mutex>
static std::map<void*,llama_model*> owners;
static std::mutex lock;
extern "C" int ov_test_create(const char*path,unsigned a,unsigned b,unsigned t,void**out){if(!out)return 1;*out=nullptr;auto p=llama_model_default_params();p.vocab_only=true;auto*m=llama_model_load_from_file(path,p);if(!m)return 1;int r=ov2_create_borrowed(m,a,b,t,out);if(r){llama_model_free(m);return r;}std::lock_guard<std::mutex>g(lock);owners[*out]=m;return 0;}
extern "C" void ov_test_destroy(void*h){if(!h)return;llama_model*m=nullptr;{std::lock_guard<std::mutex>g(lock);auto it=owners.find(h);if(it==owners.end())return;m=it->second;owners.erase(it);}ov2_destroy(h);llama_model_free(m);}
extern "C" int ov_test_owner_survives(const char*path){auto p=llama_model_default_params();p.vocab_only=true;auto*m=llama_model_load_from_file(path,p);if(!m)return 1;void*h=nullptr;int r=ov2_create_borrowed(m,3,2,60000,&h);if(r){llama_model_free(m);return r;}ov2_destroy(h);auto*v=llama_model_get_vocab(m);bool ok=v&&llama_vocab_n_tokens(v)>0;llama_model_free(m);return ok?0:1;}
extern "C" llama_model* ov_test_load_vocab(const char*path){auto p=llama_model_default_params();p.vocab_only=true;return llama_model_load_from_file(path,p);}
extern "C" void ov_test_free_model(llama_model*m){llama_model_free(m);}
