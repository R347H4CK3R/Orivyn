import Foundation
import Glibc

// Storage/reload boundaries are explicit in-memory doubles, not actual Keychain.
@MainActor enum KeychainService {
    static var values: [Data:String] = [:]
    static var writes = 0, reads = 0
    static func read(endpoint: String) throws -> String? { reads += 1; return values[Data(endpoint.utf8)] }
    static func save(_ value: String, endpoint: String) throws { writes += 1; values[Data(endpoint.utf8)] = value.isEmpty ? nil : value }
}
@MainActor final class MemoryDefaults { var changes = 0; func set(_ value: Any, forKey: String) { changes += 1 } }
@MainActor final class SaveScaffold {
    var remoteBaseURL = "https://old.example/v1", remoteModelName = "old", remoteEnabled = true
    let defaults = MemoryDefaults()
    var errors = 0, reloads = 0
    func report(_ error: any Error) { errors += 1 }
    func reloadProviders() async throws { reloads += 1 }
    // PRODUCTION_METHODS
}
@main struct RemoteSaveSmoke {
    @MainActor static func main() async throws {
        var checks: [[String:Any]] = []
        let old = "https://old.example/v1", new = "https://new.example/v1"
        func setup() -> SaveScaffold { KeychainService.values = [Data(old.utf8):"old-fixture",Data(new.utf8):"historical-fixture"]; KeychainService.reads = 0; KeychainService.writes = 0; return SaveScaffold() }
        do {
            let s = setup(); await s.saveRemote(baseURL: " \(old) \n", model: "chat", credentialIntent: .keepExisting, enabled: true)
            checks.append(["check":"keep exact normalized endpoint does not read or write key", "passed":KeychainService.reads == 0 && KeychainService.writes == 0 && s.reloads == 1 && s.remoteBaseURL == old])
        }
        do {
            let s = setup(); await s.saveRemote(baseURL: new, model: "chat", credentialIntent: .none, enabled: true)
            checks.append(["check":"none with historical target key refuses without changing settings or any key", "passed":s.errors == 1 && s.remoteBaseURL == old && s.defaults.changes == 0 && KeychainService.writes == 0 && KeychainService.values[Data(new.utf8)] == "historical-fixture" && KeychainService.values[Data(old.utf8)] == "old-fixture"])
        }
        do {
            let s = setup(); KeychainService.values[Data(new.utf8)] = nil
            await s.saveRemote(baseURL: new, model: "chat", credentialIntent: .none, enabled: true)
            checks.append(["check":"none at unused endpoint writes no key", "passed":s.errors == 0 && s.remoteBaseURL == new && KeychainService.writes == 0 && KeychainService.values[Data(old.utf8)] == "old-fixture"])
        }
        do {
            let s = setup(); await s.saveRemote(baseURL: new, model: "chat", credentialIntent: .remove, enabled: true)
            checks.append(["check":"explicit remove affects target only", "passed":KeychainService.writes == 1 && KeychainService.values[Data(new.utf8)] == nil && KeychainService.values[Data(old.utf8)] == "old-fixture" && s.errors == 0])
        }
        do {
            let s = setup(); await s.saveRemote(baseURL: new, model: "chat", credentialIntent: .replace("replacement-fixture"), enabled: true)
            checks.append(["check":"replacement affects target only", "passed":KeychainService.values[Data(new.utf8)] == "replacement-fixture" && KeychainService.values[Data(old.utf8)] == "old-fixture" && KeychainService.writes == 1])
        }
        do {
            let s = setup(); await s.saveRemote(baseURL: new, model: "chat", credentialIntent: .keepExisting, enabled: true)
            checks.append(["check":"keep cannot cross endpoints", "passed":s.errors == 1 && KeychainService.writes == 0 && s.defaults.changes == 0])
        }
        do {
            let s = setup(); await s.saveRemote(baseURL: "http://invalid.example", model: "chat", credentialIntent: .replace("fixture"), enabled: true)
            checks.append(["check":"invalid enabled endpoint rejected before credential changes", "passed":s.errors == 1 && KeychainService.writes == 0 && s.defaults.changes == 0])
        }
        do {
            let s = setup()
            let composed = "https://example.com/caf\u{00E9}/v1", decomposed = "https://example.com/cafe\u{0301}/v1"
            s.remoteBaseURL = composed
            KeychainService.values = [Data(composed.utf8): "old-fixture", Data(decomposed.utf8): "historical-fixture"]
            let intent = RemoteCredentialIntent.draft(endpoint: decomposed, savedEndpoint: composed, typedKey: "", remove: false)
            await s.saveRemote(baseURL: decomposed, model: "chat", credentialIntent: intent, enabled: true)
            checks.append(["check":"canonically equal byte-distinct endpoint refuses historical key reuse", "passed":intent == .none && s.errors == 1 && s.defaults.changes == 0 && KeychainService.writes == 0 && KeychainService.values[Data(composed.utf8)] == "old-fixture" && KeychainService.values[Data(decomposed.utf8)] == "historical-fixture"])
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject:["checks":checks,"realKeychainVerified":false,"nativeUIVerified":false],options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
        if checks.contains(where: { $0["passed"] as? Bool != true }) { exit(1) }
    }
}
