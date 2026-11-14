import Foundation
let source = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
let ids = ["abcdefab-1234-1234-1234-123456789abc", "12345678-1234-1234-1234-123456789abc"]
for count in 0...2 { for first in [false,true] {
 let grammar = try LocalAgentGrammar.constrain(source, requireTool:first, conversationIDs:Array(ids.prefix(count)))
 try grammar.write(toFile:CommandLine.arguments[2]+"/policy-\(count)-\(first).gbnf",atomically:true,encoding:.utf8)
}}
