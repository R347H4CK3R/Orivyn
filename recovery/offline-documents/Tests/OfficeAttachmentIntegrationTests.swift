import XCTest
@testable import JarvisEVO

/// Run only after proposed/office-integration.diff has been reviewed and applied.
@MainActor
final class OfficeAttachmentIntegrationTests: XCTestCase {
    private var root: URL!
    private var service: AttachmentService!
    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory: true)
        service = try AttachmentService(directory: root.appendingPathComponent("Attachments",isDirectory: true))
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: root) }
    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: name,withExtension: nil,subdirectory: "OfficeFixtures"))
    }
    func testOfficeAndDelimitedImportsKeepIndependentOriginalsAndFrontloadModelNotes() throws {
        for (name,mime) in [("paragraphs-tables.docx","application/vnd.openxmlformats-officedocument.wordprocessingml.document"),
                            ("types-and-formulas.xlsx","application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"),
                            ("structured.csv","text/csv"),("structured.tsv","text/tab-separated-values")] {
            let original = try Data(contentsOf: fixture(name))
            let source = root.appendingPathComponent(name)
            try original.write(to: source)
            let imported = try service.importFile(at: source)
            let stored = try XCTUnwrap(service.url(for: imported))
            XCTAssertNotEqual(source,stored)
            XCTAssertEqual(imported.relativePath, imported.id.uuidString + "." + source.pathExtension)
            XCTAssertEqual(imported.mediaType,mime)
            XCTAssertNil(imported.previewRelativePath)
            try FileManager.default.removeItem(at: source)
            XCTAssertEqual(try Data(contentsOf: stored),original)
            let message = ChatMessage(role: .user,content: "Analyze",attachments: [imported])
            XCTAssertTrue(message.promptContent.contains("Untrusted document content"))
            XCTAssertTrue(message.promptContent.contains("not executed"))
            let roundTrip = try JSONDecoder().decode(ChatAttachment.self,from: JSONEncoder().encode(imported))
            XCTAssertEqual(roundTrip,imported)
        }
    }
    func testFailedOfficeExtractionRemovesStagedCopy() throws {
        let before = try FileManager.default.contentsOfDirectory(atPath: service.directory.path)
        XCTAssertThrowsError(try service.importFile(at: fixture("entity.docx")))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: service.directory.path),before)
    }
    func testRepeatingOfficeImportGetsIndependentOwnership() throws {
        let url = try fixture("paragraphs-tables.docx")
        let a = try service.importFile(at: url), b = try service.importFile(at: url)
        XCTAssertNotEqual(a.relativePath,b.relativePath)
        service.remove(a)
        XCTAssertNotNil(service.url(for: b))
    }
    func testCancellationAfterStagingAndDuringExtractionRemovesOwnedOriginal() async throws {
        let source = try fixture("paragraphs-tables.docx")
        for phase in [OfficeReadPhase.stagedOriginal,.decompressedChunk] {
            let reader = OfflineDocumentReader(control: OfficeReadControl { current in
                if current == phase { withUnsafeCurrentTask { $0?.cancel() } }
            })
            let owned = try AttachmentService(directory: service.directory,officeReader: reader)
            let before = try FileManager.default.contentsOfDirectory(atPath: service.directory.path)
            let cancelled = await Task.detached {
                do { _ = try owned.importFile(at: source); return false }
                catch is CancellationError { return true }
                catch { return false }
            }.value
            XCTAssertTrue(cancelled)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: service.directory.path),before)
        }
    }
    func testOldHistoryStillDecodesWithoutNewFields() throws {
        let json = #"{"id":"DC6EE924-6307-46F8-A232-BEFEB4B4F733","name":"notes.txt","relativePath":"notes.txt","mediaType":"text/plain","byteCount":5,"extractedText":"hello"}"#
        let old = try JSONDecoder().decode(ChatAttachment.self,from: Data(json.utf8))
        XCTAssertNil(old.previewRelativePath)
        XCTAssertEqual(old.extractedText,"hello")
    }
}
