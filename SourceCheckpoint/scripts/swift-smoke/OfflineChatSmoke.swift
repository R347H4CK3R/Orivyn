import Foundation
import llama

/// Host integration of exact stores, context builder and actual inference actor.
/// The driver orchestrates these components; it is not the SwiftUI AppModel.
@main struct OfflineChatSmoke {
    enum Failure: Error { case failed(String) }
    static func main() async {
        do { try await run() }
        catch { FileHandle.standardError.write(Data("Offline chat failed: \(error)\n".utf8)); exit(1) }
    }

    static func run() async throws {
        guard CommandLine.arguments.count == 4 else { throw Failure.failed("Explicit model, runtime and isolated data directory required") }
        let modelURL = URL(fileURLWithPath: CommandLine.arguments[1])
        CommandLine.arguments[2].withCString { ggml_backend_load_all_from_path($0) }
        let directory = URL(fileURLWithPath: CommandLine.arguments[3])
        let database = directory.appendingPathComponent("chat.sqlite")
        let initialStore = try SQLiteConversationStore(url: database)
        let note = MemoryNote(content: "My project codename is Silver Badger.")
        try await initialStore.saveMemory(note)
        let history = Conversation(title: "History acceptance", messages: [
            ChatMessage(role: .user, content: "My test robot is named Copper Owl."),
            ChatMessage(role: .assistant, content: "Your test robot is named Copper Owl.")
        ])
        try await initialStore.save(history)
        let text = "The document project codename is Cobalt Finch."
        let document = ChatAttachment(name: "project.txt", relativePath: "project.txt", mediaType: "text/plain", byteCount: text.utf8.count, extractedText: text)
        let documentHistory = Conversation(title: "Document acceptance", messages: [
            ChatMessage(role: .user, content: "What is the project codename in the attached document? Reply with its codename only.", attachments: [document])
        ])
        try await initialStore.save(documentHistory)
        // A separate real SQLite connection reads the persisted inputs.
        let reopened = try SQLiteConversationStore(url: database)
        guard let savedHistory = try await reopened.load(id: history.id),
              let savedDocument = try await reopened.load(id: documentHistory.id),
              try await reopened.memories() == [note] else { throw Failure.failed("Persisted inputs did not reopen") }
        print("PASS persisted history, document text and memory reopen")
        let engine = LlamaEngine()
        do {
            var followup = savedHistory
            followup.messages.append(ChatMessage(role: .user, content: "What is my test robot named? Reply with its name only."))
            try await generateAndPersist(followup, system: "Answer from the conversation only.", expected: "copper owl", store: reopened, engine: engine, model: modelURL)
            print("PASS reopened conversation produces and persists correct follow-up")

            try await generateAndPersist(savedDocument, system: "Answer from the attached data only.", expected: "cobalt finch", store: reopened, engine: engine, model: modelURL)
            print("PASS reopened document text produces and persists correct answer")

            let query = "What is my saved project codename? Reply with its codename only."
            let notes = try await reopened.memories()
            let selected = MemoryContextBuilder.build(notes: notes, query: query)
            guard selected.includedCount == 1 else { throw Failure.failed("Persisted note not selected") }
            let memoryChat = Conversation(title: "Memory acceptance", messages: [ChatMessage(role: .user, content: query)])
            try await generateAndPersist(memoryChat, system: "Answer from the saved notes. " + selected.text, expected: "silver badger", store: reopened, engine: engine, model: modelURL)
            print("PASS persisted memory selection grounds actual answer")

            let verified = try SQLiteConversationStore(url: database)
            let completed = try await verified.list(includeArchived: true)
            guard completed.count == 3, completed.allSatisfy({ $0.messages.last?.role == .assistant && $0.messages.last?.state == .complete }) else {
                throw Failure.failed("Completed responses did not survive reopen")
            }
            print("PASS generated complete responses survive separate connection reopen")
            let backup = try await verified.exportData()
            let restored = try SQLiteConversationStore(url: directory.appendingPathComponent("restored.sqlite"))
            try await restored.importData(backup)
            let restoredConversations = try await restored.list(includeArchived: true)
            let restoredNotes = try await restored.memories()
            guard Dictionary(uniqueKeysWithValues: completed.map { ($0.id, $0) }) ==
                  Dictionary(uniqueKeysWithValues: restoredConversations.map { ($0.id, $0) }),
                  restoredNotes == notes else { throw Failure.failed("Backup restore changed generated conversation data") }
            print("PASS actual generated history and memory backup restore exactly")
            await engine.unload()
        } catch {
            await engine.unload()
            throw error
        }
    }

    static func generateAndPersist(_ original: Conversation, system: String, expected: String,
                                   store: SQLiteConversationStore, engine: LlamaEngine, model: URL) async throws {
        var conversation = original
        let request = GenerationRequest(messages: original.messages, systemPrompt: system, maxTokens: 64, temperature: 0)
        conversation.messages.append(ChatMessage(role: .assistant, content: "", state: .streaming))
        try await store.save(conversation)
        let index = conversation.messages.count - 1
        do {
            for try await piece in try await engine.stream(request, modelURL: model) {
                conversation.messages[index].content += piece
                try await store.save(conversation)
            }
            guard conversation.messages[index].content.lowercased().contains(expected) else {
                throw Failure.failed("Unexpected actual answer: \(conversation.messages[index].content)")
            }
            conversation.messages[index].state = .complete
            try await store.save(conversation)
        } catch {
            conversation.messages[index].state = .failed
            try await store.save(conversation)
            throw error
        }
    }
}
