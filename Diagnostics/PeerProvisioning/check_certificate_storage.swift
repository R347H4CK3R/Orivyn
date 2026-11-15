import Foundation
import Security

/// Public certificate fixtures only; no Keychain enumeration or private-key access.
@main
struct CertificateStorageProbe {
    struct Result: Codable {
        let mode: String
        let addStatus: OSStatus
        let labelUpdateStatus: OSStatus?
        let lookupWithNonSync: OSStatus
        let lookupWithoutNonSync: OSStatus
        let exactDERMatches: Bool
        let cleanupStatus: OSStatus
    }
    enum Failure: Error { case invalidArguments, invalidFixture, unexpectedReturnType, certificateLookupRegression }
    static func stage(_ value: String) {
        FileHandle.standardError.write(Data(("STORAGE_STAGE " + value + "\n").utf8))
    }
    static func check(der: Data, updateLabel: Bool) throws -> Result {
        let mode = updateLabel ? "reference-with-explicit-label-update" : "reference-add-only"
        stage(mode + " create-certificate begin")
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else { throw Failure.invalidFixture }
        stage(mode + " create-certificate complete")
        let label = "orivyn.storage.probe." + UUID().uuidString
        let add: [CFString: Any] = [
            kSecClass: kSecClassCertificate, kSecValueRef: certificate, kSecAttrLabel: label,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable: false
        ]
        stage(mode + " add begin")
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        stage(mode + " add returned status=" + String(addStatus))
        let exactItem: [CFString: Any] = [kSecClass: kSecClassCertificate, kSecValueRef: certificate]
        var labelStatus: OSStatus?
        if addStatus == errSecSuccess && updateLabel {
            stage(mode + " exact-label-update begin")
            labelStatus = SecItemUpdate(exactItem as CFDictionary, [kSecAttrLabel: label] as CFDictionary)
            stage(mode + " exact-label-update returned status=" + String(labelStatus!))
        }
        var query: [CFString: Any] = [
            kSecClass: kSecClassCertificate, kSecAttrLabel: label,
            kSecAttrSynchronizable: false, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne
        ]
        var found: CFTypeRef?
        stage(mode + " lookup-nonsync begin")
        let withNonSync = SecItemCopyMatching(query as CFDictionary, &found)
        stage(mode + " lookup-nonsync returned status=" + String(withNonSync))
        let exact: Bool
        if let found {
            stage(mode + " lookup result-type=" + String(CFGetTypeID(found)))
            guard CFGetTypeID(found) == CFDataGetTypeID(), let bytes = found as? Data else { throw Failure.unexpectedReturnType }
            exact = bytes == der
        } else { exact = false }
        query.removeValue(forKey: kSecAttrSynchronizable)
        var without: CFTypeRef?
        stage(mode + " lookup-default begin")
        let withoutNonSync = SecItemCopyMatching(query as CFDictionary, &without)
        stage(mode + " lookup-default returned status=" + String(withoutNonSync))
        var cleanup = errSecItemNotFound
        if addStatus == errSecSuccess {
            stage(mode + " cleanup-exact-certificate begin")
            cleanup = SecItemDelete(exactItem as CFDictionary)
            stage(mode + " cleanup returned status=" + String(cleanup))
        }
        return Result(mode: mode, addStatus: addStatus, labelUpdateStatus: labelStatus,
            lookupWithNonSync: withNonSync, lookupWithoutNonSync: withoutNonSync,
            exactDERMatches: exact, cleanupStatus: cleanup)
    }

    static func main() throws {
        guard CommandLine.arguments.count == 4 else { throw Failure.invalidArguments }
        stage("main begin")
        let baseline = try check(der: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])), updateLabel: false)
        let candidate = try check(der: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])), updateLabel: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var report = try encoder.encode([baseline, candidate]); report.append(10)
        FileHandle.standardOutput.write(report)
        guard candidate.addStatus == errSecSuccess, candidate.labelUpdateStatus == errSecSuccess,
              candidate.lookupWithNonSync == errSecSuccess, candidate.exactDERMatches,
              candidate.cleanupStatus == errSecSuccess else { throw Failure.certificateLookupRegression }
        try Data("PASS".utf8).write(to: URL(fileURLWithPath: CommandLine.arguments[3]), options: .atomic)
        stage("main passed")
    }
}
