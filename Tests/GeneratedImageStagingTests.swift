import XCTest
@testable import JarvisEVO

final class GeneratedImageStagingTests: XCTestCase {
    private var root: URL!
    private var staging: GeneratedImageStaging!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        staging = try GeneratedImageStaging(directory: root.appendingPathComponent("Staging", isDirectory: true))
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testOwnedCopySurvivesSourceDeletionAndStagerRecreation() throws {
        // Staging preserves bounded bytes, not image validity; the importer validates pixels later.
        let bytes = Data([1, 2, 3, 4])
        let source = try write(bytes)
        let owned = try staging.stage(from: source)
        XCTAssertNotEqual(owned, source)
        try FileManager.default.removeItem(at: source)
        staging = try GeneratedImageStaging(directory: staging.directory)
        XCTAssertEqual(try Data(contentsOf: owned), bytes)
        try staging.discard(owned)
        XCTAssertFalse(FileManager.default.fileExists(atPath: owned.path))
    }

    func testCopiesUseUniqueDirectChildNames() throws {
        let source = try write(Data([1]))
        let first = try staging.stage(from: source)
        let second = try staging.stage(from: source)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.deletingLastPathComponent(), staging.directory)
        XCTAssertEqual(first.pathExtension, "png")
        XCTAssertNotNil(UUID(uuidString: first.deletingPathExtension().lastPathComponent))
        XCTAssertEqual(try contents().count, 2)
    }

    func testByteLimitAcceptsExactBoundaryAndRejectsEmptyOrOversizedWithoutOrphans() throws {
        for size in [0, AttachmentService.maximumBytes + 1] {
            let source = try write(Data(repeating: 1, count: size))
            XCTAssertThrowsError(try staging.stage(from: source))
            XCTAssertTrue(try contents().isEmpty)
        }
        let source = try write(Data(repeating: 1, count: AttachmentService.maximumBytes))
        let owned = try staging.stage(from: source)
        XCTAssertEqual(try Data(contentsOf: owned).count, AttachmentService.maximumBytes)
    }

    func testRejectsRemoteDirectorySymlinkAndUnsupportedExtensionWithoutOrphans() throws {
        let source = try write(Data([1]))
        let link = root.appendingPathComponent("link.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        let invalid = try write(Data([1]), name: "unsupported.txt")
        for url in [URL(string: "https://example.com/image.png")!, root!, link, invalid] {
            XCTAssertThrowsError(try staging.stage(from: url))
            XCTAssertTrue(try contents().isEmpty)
        }
    }

    func testUnavailableDestinationDoesNotLeakAnOwnedFile() throws {
        let source = try write(Data([1]))
        try FileManager.default.removeItem(at: staging.directory)
        try Data([9]).write(to: staging.directory)
        XCTAssertThrowsError(try staging.stage(from: source))
        XCTAssertEqual(try Data(contentsOf: staging.directory), Data([9]))
        XCTAssertEqual(try Data(contentsOf: source), Data([1]))
    }

    func testDiscardRejectsFilesOutsideOwnedDirectory() throws {
        let source = try write(Data([1]))
        XCTAssertThrowsError(try staging.discard(source))
        XCTAssertEqual(try Data(contentsOf: source), Data([1]))
    }

    func testRejectsSymlinkStagingRootAndLaterDirectoryReplacement() throws {
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: staging.directory)
        XCTAssertThrowsError(try GeneratedImageStaging(directory: alias))
        let source = try write(Data([1]))
        let outside = root.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.removeItem(at: staging.directory)
        try FileManager.default.createSymbolicLink(at: staging.directory, withDestinationURL: outside)
        XCTAssertThrowsError(try staging.stage(from: source))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    func testOwnedStagingIsExcludedFromBackupAndProtected() throws {
        let source = try write(Data([1]))
        let owned = try staging.stage(from: source)
        XCTAssertEqual(try staging.directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        let attributes = try FileManager.default.attributesOfItem(atPath: owned.path)
        // FileAttributeKey.protectionKey returns NSString, not the Swift raw-value struct.
        let rawProtection = attributes[.protectionKey]
        XCTAssertEqual(rawProtection as? String, FileProtectionType.complete.rawValue,
            "Returned protection: \(String(describing: rawProtection)); type: \(rawProtection.map { String(reflecting: type(of: $0)) } ?? "nil")")
    }

    func testPolicyRequiresSupportedDeviceAndExactlyIOS26() {
        XCTAssertTrue(ImageCreationAvailability.isAvailable(supportsImagePlayground: true, osMajorVersion: 26))
        XCTAssertFalse(ImageCreationAvailability.isAvailable(supportsImagePlayground: false, osMajorVersion: 26))
        for version in [18, 25, 27, 28] {
            XCTAssertFalse(ImageCreationAvailability.isAvailable(supportsImagePlayground: true, osMajorVersion: version))
        }
    }

    func testConceptValidationUsesUTF8BytesAndRejectsNULOrWhitespace() {
        XCTAssertTrue(ImageCreationAvailability.isValidConcept("A blue bird"))
        XCTAssertTrue(ImageCreationAvailability.isValidConcept(String(repeating: "😀", count: 256)))
        XCTAssertFalse(ImageCreationAvailability.isValidConcept(String(repeating: "😀", count: 257)))
        XCTAssertFalse(ImageCreationAvailability.isValidConcept(" \n\t"))
        XCTAssertFalse(ImageCreationAvailability.isValidConcept("Bird\0tree"))
    }

    private func write(_ data: Data, name: String = "source.png") throws -> URL {
        let url = root.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }
    private func contents() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: staging.directory, includingPropertiesForKeys: nil)
    }
}
