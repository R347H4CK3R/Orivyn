import Foundation

/// Synchronous compensating transaction, not crash-atomic across Keychain/files.
/// The metadata closure must retain its prior metadata if it throws. Callers
/// update in-memory connection state only after this function returns normally.
/// A failed credential write must leave its previous value intact.
enum PluginConnectionRemoval {
    static func perform(readCredential: () throws -> String?,
                        writeCredential: (String?) throws -> Void,
                        saveMetadata: () throws -> Void) throws {
        let previous = try readCredential()
        try writeCredential(nil)
        do {
            try saveMetadata()
        } catch {
            let metadataError = error
            do { try writeCredential(previous) }
            catch { throw PluginConnectionRemovalError.recoveryRequired }
            throw metadataError
        }
    }
}

enum PluginConnectionRemovalError: LocalizedError, Equatable {
    case recoveryRequired
    var errorDescription: String? {
        "The connection metadata could not be saved, and its previous credential could not be restored. Removal is incomplete. Reconnect and re-enter the credential before using this connection. No credential is shown or logged."
    }
}
