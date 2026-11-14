#include "llama-grammar.h"
#include <fstream>
#include <iterator>
#include <stdexcept>
int main(int argc,char **argv) {
 if(argc!=3)return 3;
 std::ifstream file(argv[1]);std::string source((std::istreambuf_iterator<char>(file)),{});
 auto *g=llama_grammar_init_impl(nullptr,source.c_str(),"root",false,nullptr,0,nullptr,0);
 if(!g)return 3;
 bool accepted=false;
 try {for(unsigned char c:std::string(argv[2])) {llama_grammar_accept(g,c);if(llama_grammar_get_stacks(g).empty())break;}
 for(const auto &s:llama_grammar_get_stacks(g))if(s.empty())accepted=true;
 }catch(const std::runtime_error &){}
 llama_grammar_free_impl(g);return accepted?0:1;
}
