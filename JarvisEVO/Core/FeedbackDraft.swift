import Foundation

/// Explicit user-authored text only. Never collects conversations, logs or credentials.
struct FeedbackDraft {
    var title = ""
    var details = ""
    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.count <= 100
            && !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && details.count <= 4_000
    }
    var exportText: String { "# Orivyn suggestion: \(title.trimmingCharacters(in: .whitespacesAndNewlines))\n\n\(details.trimmingCharacters(in: .whitespacesAndNewlines))\n" }
    func githubDraftURL(repository: String) throws -> URL {
        guard isValid, var parts = URLComponents(string: repository), parts.scheme == "https", parts.host == "github.com",
              parts.user == nil, parts.password == nil, parts.port == nil, parts.query == nil, parts.fragment == nil else { throw FeedbackError.invalidDraftOrDestination }
        let path = parts.path.split(separator: "/", omittingEmptySubsequences: false)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        guard path.count == 3, path.first == "", path.dropFirst().allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.unicodeScalars.allSatisfy(allowed.contains) }) else { throw FeedbackError.invalidDraftOrDestination }
        parts.path += "/issues/new"
        parts.queryItems = [URLQueryItem(name: "template", value: "feature-request.md"),
                           URLQueryItem(name: "title", value: title.trimmingCharacters(in: .whitespacesAndNewlines)),
                           URLQueryItem(name: "body", value: exportText)]
        guard let url = parts.url, url.absoluteString.utf8.count <= 16_000 else { throw FeedbackError.linkTooLong }
        return url
    }
}

enum FeedbackError: LocalizedError {
    case invalidDraftOrDestination, linkTooLong, cannotOpen
    var errorDescription: String? {
        switch self {
        case .invalidDraftOrDestination: "Add a title and description within the limits. A valid project repository must be configured in this build."
        case .linkTooLong: "This draft is too long for a browser link. Export the suggestion instead."
        case .cannotOpen: "The GitHub page could not be opened. You can export the suggestion instead."
        }
    }
}
