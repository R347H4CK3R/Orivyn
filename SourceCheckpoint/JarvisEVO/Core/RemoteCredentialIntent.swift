import Foundation

/// Explicit save intent; an empty UI draft is never implicit deletion.
enum RemoteCredentialIntent: Equatable, Sendable {
    case keepExisting, replace(String), remove, none

    static func normalizedEndpoint(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func sameEndpoint(_ first: String, _ second: String) -> Bool { normalizedEndpoint(first).utf8.elementsEqual(normalizedEndpoint(second).utf8) }
    static func draft(endpoint: String, savedEndpoint: String, typedKey: String, remove: Bool) -> Self {
        if remove { return .remove }
        if !typedKey.isEmpty { return .replace(typedKey) }
        let target = normalizedEndpoint(endpoint)
        return !target.isEmpty && sameEndpoint(target, savedEndpoint) ? .keepExisting : .none
    }
    /// nil means no Keychain write; empty String means explicit deletion.
    /// Presence is queried by the storage caller for .none, never by the UI.
    func valueToWrite(endpoint: String, savedEndpoint: String, hasExistingCredential: Bool = false) throws -> String? {
        switch self {
        case .keepExisting:
            let target = Self.normalizedEndpoint(endpoint)
            guard !target.isEmpty, Self.sameEndpoint(target, savedEndpoint) else { throw RemoteCredentialIntentError.endpointChanged }
            return nil
        case .replace(let value):
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  value.utf8.count <= 8192,
                  !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw RemoteCredentialIntentError.invalidKey }
            return value
        case .remove: return ""
        case .none:
            guard !hasExistingCredential else { throw RemoteCredentialIntentError.existingKey }
            return nil
        }
    }
}

enum RemoteCredentialIntentError: LocalizedError {
    case endpointChanged, invalidKey, existingKey
    var errorDescription: String? {
        switch self {
        case .endpointChanged: "The endpoint changed. Review the API key choice before saving. No key was changed."
        case .invalidKey: "Enter a nonempty API key within 8,192 UTF-8 bytes without control characters, or leave the replacement field empty."
        case .existingKey: "A key already exists for this endpoint. Enter a replacement or explicitly choose Remove saved key. No key was changed."
        }
    }
}
