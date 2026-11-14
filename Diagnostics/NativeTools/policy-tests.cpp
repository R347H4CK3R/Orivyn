#include "bridge.h"
#include "llama.h"
#include <iostream>
#include <stdexcept>
#include <cstring>
void check(bool v,const char*m){if(!v)throw std::runtime_error(m);}
int main(int argc,char**argv){
 if(argc!=3)return 2;llama_backend_init();
 const char*goal="Read the application identity and installed models.";
 for(unsigned expected=1;expected<=2;++expected){
  auto mp=llama_model_default_params();mp.n_gpu_layers=0;
  auto*m=llama_model_load_from_file(argv[expected],mp);check(m,"model");
  for(unsigned policy:{0u,1u,2u,3u,999u}){
   void*h=nullptr;int r=ov4_create_borrowed(m,policy,3,2,60000,goal,strlen(goal),&h);
   check((r==0)==(policy==expected),"exact policy match");check((h!=nullptr)==(policy==expected),"null rejected handle");ov2_destroy(h);
  }
  for(bool legacy:{false,true}){void*h=nullptr;int r=legacy?ov2_create_borrowed(m,3,2,60000,&h):ov3_create_borrowed(m,3,2,60000,goal,strlen(goal),&h);check((r==0)==(expected==1),"legacy policy unchanged");check((h!=nullptr)==(expected==1),"legacy rejected handle");ov2_destroy(h);}
  void*h=nullptr;check(ov4_create_borrowed(m,expected,4,2,60000,goal,strlen(goal),&h)!=0&&!h,"mask boundary");check(ov4_create_borrowed(m,expected,3,2,60001,goal,strlen(goal),&h)!=0&&!h,"TTL boundary");check(ov4_create_borrowed(m,expected,3,2,60000,"x\0y",3,&h)!=0&&!h,"goal boundary");
  llama_model_free(m);
 }
 llama_backend_free();std::cout<<"PASS policy1/2 exact-template matches, cross-policy/unknown rejection, legacy ov2/ov3 behavior, mask/TTL/NUL boundaries\n";
}
