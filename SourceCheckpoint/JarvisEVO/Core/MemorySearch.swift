import Foundation

/// Literal local matching only, never a model or remote lookup.
enum MemorySearch {
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
