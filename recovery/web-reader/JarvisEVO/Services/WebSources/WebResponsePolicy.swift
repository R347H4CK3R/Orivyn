import Foundation

enum WebResponsePolicy {
    static func validate(status: Int, fields: [(String, String)]) throws -> String {
        if (300...399).contains(status) { throw WebSourceError.redirectBlocked }
        if status == 401 || status == 403 || status == 407 { throw WebSourceError.authenticationRequired }
        if status == 429 { throw WebSourceError.rateLimited }
        guard status == 200 else { throw WebSourceError.httpStatus(status) }
        let headers = Dictionary(grouping: fields, by: { $0.0.lowercased() }).mapValues { $0.map(\.1) }
        func single(_ name: String) throws -> String? {
            guard let values = headers[name] else { return nil }
            guard values.count == 1 else { throw WebSourceError.invalidResponse }
            return values[0].trimmingCharacters(in: .whitespaces)
        }
        if let encoding = try single("content-encoding"), encoding.lowercased() != "identity" { throw WebSourceError.encodedResponse }
        if let size = try single("content-length") {
            guard !size.isEmpty, size.utf8.allSatisfy({ (48...57).contains($0) }), let count = Int(size) else { throw WebSourceError.invalidResponse }
            guard count <= WebSourceLimits.bodyBytes else { throw WebSourceError.bodyTooLarge }
            guard headers["transfer-encoding"] == nil else { throw WebSourceError.invalidResponse }
        }
        if let transfer = try single("transfer-encoding"), transfer.lowercased() != "chunked" { throw WebSourceError.invalidResponse }
        guard let rawType = try single("content-type") else { throw WebSourceError.unsupportedContentType }
        let parts = rawType.lowercased().split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let mediaType = parts.first, ["text/plain", "text/html"].contains(mediaType) else { throw WebSourceError.unsupportedContentType }
        for parameter in parts.dropFirst() {
            guard parameter == "charset=utf-8" || parameter == "charset=\"utf-8\"" else { throw WebSourceError.unsupportedContentType }
        }
        return mediaType
    }
}
