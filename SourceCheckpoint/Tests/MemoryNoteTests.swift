import XCTest
@testable import JarvisEVO

final class MemoryNoteTests: XCTestCase {
    func testExistingStoredMemorySchemaDecodesWithoutMigration() throws {
        let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let data = Data(#"{"id":"11111111-2222-3333-4444-555555555555","content":"Original note","createdAt":123}"#.utf8)
        let note = try JSONDecoder().decode(MemoryNote.self, from: data)
        XCTAssertEqual(note.id, id)
        XCTAssertEqual(note.content, "Original note")
        XCTAssertEqual(note.createdAt, Date(timeIntervalSinceReferenceDate: 123))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(note)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set(["id", "content", "createdAt"]))
    }
    func testUnicodeAndControlTextRoundTripsUnchanged() throws {
        let note = MemoryNote(content: "Café\u{0}\n日本語🦉", createdAt: Date(timeIntervalSinceReferenceDate: 456))
        XCTAssertEqual(try JSONDecoder().decode(MemoryNote.self, from: JSONEncoder().encode(note)), note)
    }
}
