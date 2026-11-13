import Foundation

/// Selects a contiguous, unchanged source passage. Presentation/control escaping
/// belongs to the caller, after extraction; this helper never rewrites evidence.
enum LocalSearchExcerpt {
    static func excerpt(text: String, query: String, maximumBytes: Int = 160) -> String {
        let budget = min(160, max(0, maximumBytes))
        guard budget > 0, !text.isEmpty else { return "" }
        if text.utf8.prefix(budget + 1).count <= budget { return text }
        var start = text.unicodeScalars.startIndex
        if !query.isEmpty,
           let match = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive],
                                  locale: Locale(identifier: "en_US_POSIX")),
           let matchStart = match.lowerBound.samePosition(in: text.unicodeScalars) {
            start = matchStart
            let matchBytes = text[match].utf8.prefix(budget + 1).count
            // Long matches get all available bytes; shorter matches retain some
            // preceding context while reserving enough room for the whole match.
            let beforeBudget = max(0, budget - matchBytes) / 2
            var beforeBytes = 0
            while start > text.unicodeScalars.startIndex {
                let previous = text.unicodeScalars.index(before: start)
                let size = utf8Size(text.unicodeScalars[previous])
                guard size <= beforeBudget - beforeBytes else { break }
                beforeBytes += size
                start = previous
            }
        }
        var end = start
        var used = 0
        while end < text.unicodeScalars.endIndex {
            let size = utf8Size(text.unicodeScalars[end])
            guard size <= budget - used else { break }
            used += size
            text.unicodeScalars.formIndex(after: &end)
        }
        return String(text.unicodeScalars[start..<end])
    }

    private static func utf8Size(_ scalar: Unicode.Scalar) -> Int {
        switch scalar.value {
        case 0...0x7f: return 1
        case 0x80...0x7ff: return 2
        case 0x800...0xffff: return 3
        default: return 4
        }
    }
}
