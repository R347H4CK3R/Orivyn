import CryptoKit
import Foundation
import Security

/// Separate from inference-provider credentials. Saving is an explicit UI choice.
struct PluginCredentialStore {
    private static let service = "app.jarvisevo.plugins.v1"
    private static func key(_ endpoint: String) -> [String: Any] {
        let account = SHA256.hash(data: Data(endpoint.utf8)).map { String(format: "%02x", $0) }.joined()
        return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    static func read(endpoint: String) throws -> String? {
        var query = key(endpoint); query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?; let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data, let token = String(data: data, encoding: .utf8) else { throw PluginBrokerError.credentials }
        return token
    }
    static func save(_ token: String?, endpoint: String) throws {
        let query = key(endpoint)
        guard let token, !token.isEmpty else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw PluginBrokerError.credentials }; return
        }
        let data = Data(token.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw PluginBrokerError.credentials }
        } else if status != errSecSuccess { throw PluginBrokerError.credentials }
    }
}
