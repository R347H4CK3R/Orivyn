import Foundation

/// Fit whole result items into the model-agent's existing result budget. This
/// never cuts JSON or edits an item; omitted items are explicitly counted.
enum LocalToolResultBudget {
    static func encode(_ value: MCPJSONValue, collection: String, maximumBytes: Int) throws -> Data {
        guard (128...20_480).contains(maximumBytes),
              ["matches", "models", "memories", "capabilities"].contains(collection),
              var object = value.objectValue, var items = object[collection]?.arrayValue,
              object["resultTruncated"] == nil, object["omittedItems"] == nil else { throw LocalAgentError.invalidState }
        let original = try value.encoded(maximumBytes: 32_768)
        if original.count <= maximumBytes { return original }
        let total = items.count
        object["resultTruncated"] = .bool(true)
        while !items.isEmpty {
            items.removeLast()
            object[collection] = .array(items)
            object["omittedItems"] = .integer(Int64(total - items.count))
            let encoded = try MCPJSONValue.object(object).encoded(maximumBytes: 32_768)
            if encoded.count <= maximumBytes { return encoded }
        }
        // Large scalar metadata is not silently deleted to force a result through.
        throw LocalAgentError.outputBound
    }
}
