import Foundation

/// Literal search of already-extracted attachment text. No file access, model, or network.
/// Offsets are Swift Character positions in the original extracted text, never PDF page numbers.
enum AttachmentTextSearch {
    struct Match: Equatable, Sendable {
        let offset: Int
        let length: Int
        let snippet: String
        let snippetOffset: Int
    }
    struct Result: Equatable, Sendable {
        let matches: [Match]
        let wasTextTruncated: Bool
        /// An additional match was observed within the searched prefix, not the unknown tail.
        let moreMatches: Bool
    }
    enum SearchError: LocalizedError, Equatable {
        case queryTooLarge
        var errorDescription: String? { "Search queries are limited to 256 UTF-8 bytes. Shorten your query and try again." }
    }

    static func search(text: String, query: String) throws -> Result {
        guard query.utf8.prefix(257).count <= 256 else { throw SearchError.queryTooLarge }
        // One extra Character detects truncation without traversing the remaining input.
        let prefix = text.prefix(60_001)
        let truncated = prefix.count > 60_000
        let source = String(prefix.prefix(60_000))
        guard !query.isEmpty else { return Result(matches: [], wasTextTruncated: truncated, moreMatches: false) }
        // Foundation may match a scalar inside a composed Character. Align displayed
        // ranges to original Character boundaries instead of reporting UTF-16 offsets.
        let boundaries = Array(source.indices) + [source.endIndex]
        func ceilingBoundary(_ index: String.Index) -> Int {
            var low = 0, high = boundaries.count - 1
            while low < high {
                let mid = low + (high - low) / 2
                if boundaries[mid] < index { low = mid + 1 } else { high = mid }
            }
            return low
        }
        var matches: [Match] = []
        var cursor = source.startIndex
        while cursor < source.endIndex,
              let range = source.range(of: query, options: [.caseInsensitive, .diacriticInsensitive],
                                       range: cursor..<source.endIndex,
                                       locale: Locale(identifier: "en_US_POSIX")) {
            // Defensive progress guard for any Unicode search result of zero width.
            guard range.upperBound > range.lowerBound else { break }
            if matches.count == 50 { return Result(matches: matches, wasTextTruncated: truncated, moreMatches: true) }
            let lowerCeiling = ceilingBoundary(range.lowerBound)
            let offset = boundaries[lowerCeiling] == range.lowerBound ? lowerCeiling : max(0, lowerCeiling - 1)
            let upper = ceilingBoundary(range.upperBound)
            let start = max(0, offset - 80)
            let end = min(boundaries.count - 1, start + 240)
            matches.append(Match(offset: offset, length: upper - offset,
                                 snippet: String(source[boundaries[start]..<boundaries[end]]),
                                 snippetOffset: start))
            cursor = boundaries[upper]
        }
        return Result(matches: matches, wasTextTruncated: truncated, moreMatches: false)
    }
}
