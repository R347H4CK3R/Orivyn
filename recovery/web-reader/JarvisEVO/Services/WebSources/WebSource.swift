import Foundation

/// Source IDs identify a retrieved snapshot. They establish provenance, not truth.
struct WebSource: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let originalURL: URL
    let finalURL: URL
    let retrievedAt: Date
    let mediaType: String
    let receivedBodyBytes: Int
    let title: String?
    let text: String
    let textTruncated: Bool
}

enum WebSourceLimits {
    static let bodyBytes = 262_144
    static let textBytes = 16_384
    static let titleBytes = 240
    static let htmlTokens = 10_000
    static let tagBytes = 4_096
    static let depth = 64
    static let sources = 3
}

enum WebSourceError: Error, Sendable, Equatable, LocalizedError {
    case invalidURL, unsafeAddress, hostnameIsolationUnavailable, busy, offline
    case redirectBlocked, authenticationRequired, rateLimited, httpStatus(Int)
    case encodedResponse, unsupportedContentType, bodyTooLarge, invalidResponse
    case invalidUTF8, complexHTML, emptyContent, timeout, transportUnavailable, contextTooSmall, tooManySources

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Choose an explicit public HTTPS URL without credentials, query parameters, or a fragment."
        case .unsafeAddress: "This address is not allowed for public web source retrieval."
        case .hostnameIsolationUnavailable: "This transport cannot safely pin a hostname to a public network address."
        case .busy: "A source read is already in progress."
        case .offline: "Live internet information is unavailable while offline."
        case .redirectBlocked: "This source redirects. No redirected page was retrieved; enter the destination explicitly to read it."
        case .authenticationRequired: "This page requires access that the source reader does not use."
        case .rateLimited: "The website rate-limited this request. No automatic retry was made."
        case .httpStatus(let code): "The source returned HTTP \(code)."
        case .encodedResponse: "This source requires an unsupported compressed response."
        case .unsupportedContentType: "Only UTF-8 HTML and plain-text sources are supported."
        case .bodyTooLarge: "The source exceeds the 256 KiB retrieval limit."
        case .invalidResponse: "The source returned an unsupported or invalid response."
        case .invalidUTF8: "The source is not valid UTF-8 text."
        case .complexHTML: "The source HTML is malformed or exceeds the safe extraction limits."
        case .emptyContent: "No readable text was extracted. Script-only and gated pages are not supported."
        case .timeout: "The source read timed out."
        case .transportUnavailable: "Live source retrieval is currently unavailable."
        case .contextTooSmall: "The source metadata does not fit the requested context budget."
        case .tooManySources: "Read between one and three explicit sources per request."
        }
    }
}

struct RetrievedWebBody: Sendable {
    let url: URL
    let mediaType: String
    let data: Data
}

struct BoundedWebBody: Sendable {
    private(set) var data = Data()
    mutating func append(_ chunk: Data) throws {
        guard chunk.count <= WebSourceLimits.bodyBytes - data.count else { throw WebSourceError.bodyTooLarge }
        data.append(chunk)
    }
}

struct ExtractedWebText: Sendable {
    let title: String?
    let text: String
    let truncated: Bool
}

/// A byte-bounded, valid Unicode-scalar prefix. Does not claim grapheme preservation.
func webUTF8Prefix(_ text: String, maximumBytes: Int) -> String {
    var result = String.UnicodeScalarView()
    var used = 0
    for scalar in text.unicodeScalars {
        let length = scalar.utf8.count
        guard used + length <= maximumBytes else { break }
        result.append(scalar)
        used += length
    }
    return String(result)
}
