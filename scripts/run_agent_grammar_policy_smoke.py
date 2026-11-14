#!/usr/bin/env python3
"""Validate exact Swift-generated production GBNF with an explicit local llama runtime; no model inference/downloads."""
import argparse,hashlib,json,pathlib,subprocess,runpy,shutil
p=argparse.ArgumentParser(description=__doc__)
for name in ['swiftc','llama-source','runtime','output']:p.add_argument('--'+name,required=True,type=pathlib.Path)
a=p.parse_args();root=pathlib.Path(__file__).resolve().parents[1];out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
inputs=[root/'JarvisEVO/Core/LocalAgentGrammar.swift',root/'JarvisEVO/Core/LocalAgentError.swift',root/'JarvisEVO/Resources/LocalAgentDecision.gbnf',a.llama_source/'src/llama-grammar.h',(a.runtime/'libllama.so').resolve()]
(out/'SOURCE-MANIFEST.json').write_text(json.dumps([{'path':str(f),'sha256':hashlib.sha256(f.read_bytes()).hexdigest()} for f in inputs],indent=2)+'\n')
shutil.copy(root/'JarvisEVO/Resources/LocalAgentDecision.gbnf',out/'LocalAgentDecision.gbnf')
ids=['abcdefab-1234-1234-1234-123456789abc','12345678-1234-1234-1234-123456789abc']
(out/'main.swift').write_text('''import Foundation
let source = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
let ids = ["abcdefab-1234-1234-1234-123456789abc", "12345678-1234-1234-1234-123456789abc"]
for count in 0...2 { for first in [false,true] {
 let grammar = try LocalAgentGrammar.constrain(source, requireTool:first, conversationIDs:Array(ids.prefix(count)))
 try grammar.write(toFile:CommandLine.arguments[2]+"/policy-\\(count)-\\(first).gbnf",atomically:true,encoding:.utf8)
}}
''')
sources=runpy.run_path(str(root/'scripts/run_foundation_tests.py'))['SOURCES']
with (out/'main.swift').open('a') as f:
 f.write(r'''
let query="folder/path \"quote\" \\ Unicode café 雪\nnext"
let action=LocalReadWorkflowPolicy.Action(name:"search_conversations",arguments:.object(["query":.string(query),"limit":.integer(10)]))
try LocalAgentGrammar.reviewed(.init(actions:[action],canAnswer:false)).write(toFile:CommandLine.arguments[2]+"/reviewed.gbnf",atomically:true,encoding:.utf8)
try action.decision.encoded().write(to:URL(fileURLWithPath:CommandLine.arguments[2]+"/approved-decision.json"))
try LocalAgentGrammar.reviewed(.init(actions:[],canAnswer:true)).write(toFile:CommandLine.arguments[2]+"/completed.gbnf",atomically:true,encoding:.utf8)
try LocalAgentGrammar.readPlanProposal(kind:"conversation_search").write(toFile:CommandLine.arguments[2]+"/proposal-search.gbnf",atomically:true,encoding:.utf8)
try LocalAgentGrammar.readPlanProposal(kind:"conversation_read").write(toFile:CommandLine.arguments[2]+"/proposal.gbnf",atomically:true,encoding:.utf8)
''')
subprocess.run([str(a.swiftc),*[str(root/n) for n in sources],str(out/'main.swift'),'-o',str(out/'emit')],check=True)
subprocess.run([str(out/'emit'),str(root/'JarvisEVO/Resources/LocalAgentDecision.gbnf'),str(out)],check=True)
(out/'validate.cpp').write_text('''#include "llama-grammar.h"
#include <fstream>
#include <iterator>
#include <stdexcept>
int main(int argc,char **argv) {
 if(argc!=3)return 3;
 std::ifstream file(argv[1]);std::string source((std::istreambuf_iterator<char>(file)),{});
 auto *g=llama_grammar_init_impl(nullptr,source.c_str(),"root",false,nullptr,0,nullptr,0);
 if(!g)return 3;
 bool accepted=false;
 try {llama_grammar_accept_str(*g,std::string(argv[2]));
 for(const auto &s:llama_grammar_get_stacks(g))if(s.empty())accepted=true;
 }catch(const std::runtime_error &){}
 llama_grammar_free_impl(g);return accepted?0:1;
}
''')
subprocess.run(['c++','-std=c++17','-I'+str(a.llama_source/'src'),'-I'+str(a.llama_source/'include'),'-I'+str(a.llama_source/'ggml/include'),str(out/'validate.cpp'),'-L'+str(a.runtime),'-Wl,-rpath,'+str(a.runtime),'-lllama','-o',str(out/'validate')],check=True)
results=[]
for count in range(3):
 for first in [False,True]:
  cases=[({'type':'tool','name':'search_conversations','arguments':{'query':'note','limit':1}},True),({'type':'answer','text':'fact'},not first)]
  for ident in ids+['ffffffff-ffff-ffff-ffff-ffffffffffff','saved_conversation_id']:
   cases.append(({'type':'tool','name':'read_conversation','arguments':{'id':ident,'messageIndex':0,'offset':0}},ident in ids[:count]))
  for decision,expected in cases:
   result=subprocess.run([str(out/'validate'),str(out/f'policy-{count}-{str(first).lower()}.gbnf'),json.dumps(decision)],capture_output=True,text=True)
   assert result.returncode in [0,1], result.stderr
   assert (result.returncode==0)==expected,(count,first,decision,result.stderr)
   results.append({'count':count,'requireTool':first,'decision':decision,'accepted':expected})
extra=[('proposal-search.gbnf',json.dumps({'schema':1,'kind':'conversation_search','query':'note'}),True),('proposal-search.gbnf',json.dumps({'schema':1,'kind':'conversation_read','query':'note','title':'note','messageIndexes':[1]}),False),('reviewed.gbnf',(out/'approved-decision.json').read_text(),True),('reviewed.gbnf',json.dumps({'type':'answer','text':'premature'}),False),('reviewed.gbnf',(out/'approved-decision.json').read_text().replace('folder/path','other'),False),('completed.gbnf',json.dumps({'type':'answer','text':'done'}),True),('completed.gbnf',(out/'approved-decision.json').read_text(),False),('proposal.gbnf',json.dumps({'schema':1,'kind':'conversation_read','query':'note','title':'note','messageIndexes':[1]}),True),('proposal.gbnf',json.dumps({'schema':1,'kind':'conversation_search','query':'note'}),False),('proposal.gbnf',json.dumps({'type':'tool','name':'read_conversation','arguments':{}}),False)]
for grammar,decision,expected in extra:
 result=subprocess.run([str(out/'validate'),str(out/grammar),decision],capture_output=True,text=True)
 assert result.returncode in [0,1] and (result.returncode==0)==expected,(grammar,decision,result.returncode,result.stderr)
 results.append({'grammar':grammar,'decision':decision,'accepted':expected})
(out/'RESULTS.json').write_text(json.dumps(results,indent=2)+'\n')
print(f'{len(results)} exact production grammar acceptance/rejection checks passed; no model or iOS execution.')
