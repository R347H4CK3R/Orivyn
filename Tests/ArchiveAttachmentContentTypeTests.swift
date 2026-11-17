import XCTest
@testable import JarvisEVO

final class ArchiveAttachmentContentTypeTests: XCTestCase {
    func testSignaturesOnlySelectExistingDecoderRoute() throws {
        XCTAssertEqual(try ArchiveAttachmentContentType.classify(Data([137,80,78,71,13,10,26,10])), "png")
        XCTAssertEqual(try ArchiveAttachmentContentType.classify(Data([255,216,255])), "jpg")
        XCTAssertEqual(try ArchiveAttachmentContentType.classify(Data("%PDF-1.7\n".utf8)), "pdf")
        // Deliberately incomplete images: classification is not successful import.
        XCTAssertThrowsError(try ArchiveAttachmentContentType.classify(Data([137,80,78])))
        XCTAssertThrowsError(try ArchiveAttachmentContentType.classify(Data([255,216])))
    }
    func testOnlyBoundedStillImageBrandsAreRoutedToHEIC() throws {
        func box(_ major: String, _ compatible: String = "") -> Data {
            let count = 16 + compatible.utf8.count
            var bytes: [UInt8] = [0, 0, 0, UInt8(count)]
            bytes.append(contentsOf: "ftyp".utf8)
            bytes.append(contentsOf: major.utf8)
            bytes.append(contentsOf: [0, 0, 0, 0])
            bytes.append(contentsOf: compatible.utf8)
            return Data(bytes)
        }
        XCTAssertEqual(Array(box("heic")), [0,0,0,16,102,116,121,112,104,101,105,99,0,0,0,0])
        XCTAssertEqual(Array(box("mif1", "heix")), [0,0,0,20,102,116,121,112,109,105,102,49,0,0,0,0,104,101,105,120])
        XCTAssertEqual(try ArchiveAttachmentContentType.classify(box("heic")), "heic")
        XCTAssertEqual(try ArchiveAttachmentContentType.classify(box("mif1", "heix")), "heic")
        for data in [box("mif1"), box("isom"), box("hevc"), box("avif"), Data(box("heic").dropLast()), Data([0,0,0,0])+Data("ftypheic".utf8)] {
            XCTAssertThrowsError(try ArchiveAttachmentContentType.classify(data))
        }
    }
    func testFullStrictUTF8PrintableTextWithoutBinaryControls() throws {
        for text in ["Synthetic text.\n", "Καλημέρα 世界\t🙂\r\n", "{\"answer\":42}"] {
            XCTAssertEqual(try ArchiveAttachmentContentType.classify(Data(text.utf8)), "txt")
        }
        for bytes in [Data(), Data(" \r\n\t".utf8), Data([0xC0,0xAF]), Data("text\u{0}binary".utf8), Data("text\u{7}".utf8), Data("text\u{7F}".utf8), Data("text\u{85}".utf8), Data(repeating: 65, count: 10 * 1024 * 1024 + 1)] {
            XCTAssertThrowsError(try ArchiveAttachmentContentType.classify(bytes))
        }
    }
    func testSignatureTakesPrecedenceOverTextNoFallbackToText() throws {
        XCTAssertEqual(try ArchiveAttachmentContentType.classify(Data("%PDF-not a real PDF, text must not bypass PDF decoder".utf8)), "pdf")
    }
}
