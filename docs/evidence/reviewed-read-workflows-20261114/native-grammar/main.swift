import Foundation
let source = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
let ids = ["abcdefab-1234-1234-1234-123456789abc", "12345678-1234-1234-1234-123456789abc"]
for count in 0...2 { for first in [false,true] {
 let grammar = try LocalAgentGrammar.constrain(source, requireTool:first, conversationIDs:Array(ids.prefix(count)))
 try grammar.write(toFile:CommandLine.arguments[2]+"/policy-\(count)-\(first).gbnf",atomically:true,encoding:.utf8)
}}

let query="folder/path \"quote\" \\ Unicode café 雪\nnext"
let action=LocalReadWorkflowPolicy.Action(name:"search_conversations",arguments:.object(["query":.string(query),"limit":.integer(10)]))
try LocalAgentGrammar.reviewed(.init(actions:[action],canAnswer:false)).write(toFile:CommandLine.arguments[2]+"/reviewed.gbnf",atomically:true,encoding:.utf8)
try action.decision.encoded().write(to:URL(fileURLWithPath:CommandLine.arguments[2]+"/approved-decision.json"))
try LocalAgentGrammar.reviewed(.init(actions:[],canAnswer:true)).write(toFile:CommandLine.arguments[2]+"/completed.gbnf",atomically:true,encoding:.utf8)
try LocalAgentGrammar.readPlanProposal(kind:"conversation_search").write(toFile:CommandLine.arguments[2]+"/proposal-search.gbnf",atomically:true,encoding:.utf8)
try LocalAgentGrammar.readPlanProposal(kind:"conversation_read").write(toFile:CommandLine.arguments[2]+"/proposal.gbnf",atomically:true,encoding:.utf8)
