import Foundation

/// Literal local matching only, never a model or remote lookup.
enum MemorySearch {
    struct PhraseResult: Sendable {
        let notes: [MemoryNote]
        let matchCount: Int
        let scannedCount: Int
    }

    /// One pass over the snapshot, retaining only the requested result count.
    /// This is literal substring matching, not semantic or exhaustive recall.
    static func phrase(_ notes: [MemoryNote], query: String, limit: Int) throws -> PhraseResult {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              query.utf8.count <= 256, (1...10).contains(limit) else { throw LocalAgentError.invalidState }
        var selected: [MemoryNote] = []
        var matches = 0
        for (index, note) in notes.enumerated() {
            if index % 64 == 0 { try Task.checkCancellation() }
            if note.content.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                matches += 1
                if selected.count < limit { selected.append(note) }
            }
        }
        try Task.checkCancellation()
        return PhraseResult(notes: selected, matchCount: matches, scannedCount: notes.count)
    }

    struct Page: Sendable {
        let notes: [MemoryNote]
        let totalMatches: Int
    }

    static func page(_ notes: [MemoryNote], query: String, offset: Int, limit: Int = 200) throws -> Page {
        guard query.utf8.count <= 1024, offset >= 0, (1...200).contains(limit) else { throw LocalAgentError.invalidState }
        let terms = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var selected: [MemoryNote] = []; var total = 0
        for (index, note) in notes.enumerated() {
            if index % 32 == 0 { try Task.checkCancellation() }
            let matches: Bool
            if terms.isEmpty { matches = true }
            else {
                let text = note.content.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                matches = terms.allSatisfy { text.contains($0) }
            }
            if matches {
                if total >= offset && selected.count < limit { selected.append(note) }
                total += 1
            }
        }
        try Task.checkCancellation()
        return Page(notes: selected, totalMatches: total)
    }

    static func pageAsync(_ notes: [MemoryNote], query: String, offset: Int) async throws -> Page {
        let worker = Task.detached(priority: .userInitiated) { try page(notes, query: query, offset: offset) }
        return try await withTaskCancellationHandler {
            let page = try await worker.value
            try Task.checkCancellation()
            return page
        } onCancel: { worker.cancel() }
    }

    static func matches(_ notes: [MemoryNote], query: String) -> [MemoryNote] {
        guard query.utf8.count <= 1024 else { return [] }
        let folded = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let terms = folded.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !terms.isEmpty else { return notes }
        return notes.filter { note in
            let content = note.content.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            return terms.allSatisfy { content.contains($0) }
        }
    }
}
