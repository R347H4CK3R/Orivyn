import Foundation

/// Exact bounded search snapshot for reviewed workflows. Recreated independently
/// from current history before every subsequent dispatch and final answer.
enum LocalReviewedSearch {
    static func result(plan: LocalReadPlan, conversations: [Conversation]) throws -> MCPJSONValue {
        let result=try LocalConversationSearch.search(conversations:conversations,query:plan.query,limit:10)
        let matches=result.matches.map { match in MCPJSONValue.object(["id":.string(match.id.uuidString),"title":.string(match.title),"excerpt":.string(match.excerpt),"excerptMayBeTruncated":.bool(match.excerptMayBeTruncated),"evidenceSource":.string(match.evidenceSource)]) }
        var fields:[String:MCPJSONValue] = ["matches":.array(matches),"searchedConversations":.integer(Int64(result.searchedConversations)),"searchLimited":.bool(result.searchLimited),"totalMatchesInWindow":.integer(Int64(result.totalMatchesInWindow)),"resultsLimited":.bool(result.resultsLimited)]
        if let title=plan.title { fields["approvedTitleMatchIDs"] = .array(try LocalReadWorkflowPolicy.fullTitleMatchIDs(matches:matches,title:title,conversations:conversations).map { .string($0) }) }
        return try MCPJSONValue.parse(LocalToolResultBudget.encode(.object(fields),collection:"matches",maximumBytes:4096),maximumBytes:4096)
    }
}
