import Foundation
import Security

/// Disposable public certificates only. Never enumerates the user's Keychain.
@main
struct CertificateStorageProbe {
    struct Result: Codable {
        let mode: String
        let addStatus: OSStatus
        let returnedLabelMatches: Bool
        let lookupWithNonSync: OSStatus
        let lookupWithoutNonSync: OSStatus
        let exactDERMatches: Bool
        let cleanupStatus: OSStatus
    }
    enum Failure: Error { case invalidArguments, invalidFixture, DERInsertionRegression }
    static func check(der: Data, useDER: Bool) throws -> Result {
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else { throw Failure.invalidFixture }
        let label = "orivyn.storage.probe." + UUID().uuidString
        var add: [CFString: Any] = [
            kSecClass: kSecClassCertificate, kSecAttrLabel: label,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable: false, kSecReturnAttributes: true, kSecReturnRef: true
        ]
        if useDER { add[kSecValueData] = der } else { add[kSecValueRef] = certificate }
        var added: CFTypeRef?
        let addStatus = SecItemAdd(add as CFDictionary, &added)
        let attributes = added as? [CFString: Any]
        let labelMatches = attributes?[kSecAttrLabel] as? String == label
        var query: [CFString: Any] = [
            kSecClass: kSecClassCertificate, kSecAttrLabel: label,
            kSecAttrSynchronizable: false, kSecReturnRef: true, kSecMatchLimit: kSecMatchLimitOne
        ]
        var found: CFTypeRef?
        let withNonSync = SecItemCopyMatching(query as CFDictionary, &found)
        let exact: Bool
        if let found, CFGetTypeID(found) == SecCertificateGetTypeID() {
            exact = SecCertificateCopyData(found as! SecCertificate) as Data == der
        } else { exact = false }
        query.removeValue(forKey: kSecAttrSynchronizable)
        var without: CFTypeRef?
        let withoutNonSync = SecItemCopyMatching(query as CFDictionary, &without)
        var cleanup = errSecItemNotFound
        if addStatus == errSecSuccess {
            // The reference came from this exact insertion; do not broaden deletion.
            if let stored = attributes?[kSecValueRef] {
                cleanup = SecItemDelete([
                    kSecClass: kSecClassCertificate, kSecMatchItemList: [stored]
                ] as CFDictionary)
            } else {
                cleanup = SecItemDelete([
                    kSecClass: kSecClassCertificate, kSecValueRef: certificate
                ] as CFDictionary)
            }
        }
        return Result(mode: useDER ? "DER" : "transient-reference", addStatus: addStatus,
            returnedLabelMatches: labelMatches, lookupWithNonSync: withNonSync,
            lookupWithoutNonSync: withoutNonSync, exactDERMatches: exact, cleanupStatus: cleanup)
    }

    static func main() throws {
        guard CommandLine.arguments.count == 3 else { throw Failure.invalidArguments }
        let reference = try check(der: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])), useDER: false)
        let DER = try check(der: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])), useDER: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode([reference, DER]), as: UTF8.self))
        guard DER.addStatus == errSecSuccess, DER.returnedLabelMatches,
              DER.lookupWithNonSync == errSecSuccess, DER.exactDERMatches,
              DER.cleanupStatus == errSecSuccess else { throw Failure.DERInsertionRegression }
    }
}
