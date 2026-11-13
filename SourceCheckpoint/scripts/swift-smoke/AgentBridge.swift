import Foundation

/// Test driver only. Calls exact production code; no replacement implementations.
@main struct AgentBridge {
    @MainActor static func main() {
        do { try run() }
        catch {
            FileHandle.standardError.write(Data("bridge-rejected: \(error)\n".utf8))
            exit(1)
        }
    }
    @MainActor static func run() throws {
        let args = CommandLine.arguments
        guard args.count == 4 else { fatalError("command directory id required") }
        let store = try LocalAgentStore(directory: URL(fileURLWithPath: args[2], isDirectory: true))
        switch args[1] {
        case "save":
            let data = FileHandle.standardInput.readDataToEndOfFile()
            guard let raw = String(data: data, encoding: .utf8) else { throw LocalAgentError.storage }
            try store.save(raw, id: args[3])
        case "load": FileHandle.standardOutput.write(Data(try store.load(id: args[3]).utf8))
        case "archive": try store.archive(id: args[3])
        case "restore": try store.restore(id: args[3])
        case "result":
            let rows: [MCPJSONValue] = (0..<10).map {
                .object(["id": .integer(Int64($0)), "title": .string(String(repeating: "\n", count: 96)),
                         "excerpt": .string(String(repeating: "界😀\t", count: 20))])
            }
            let result = try LocalToolResultBudget.encode(.object([
                "matches": .array(rows), "searchedConversations": .integer(10), "searchLimited": .bool(false)
            ]), collection: "matches", maximumBytes: 4096)
            FileHandle.standardOutput.write(result)
        default: throw LocalAgentError.invalidState
        }
    }
}
