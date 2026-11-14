import XCTest
@testable import JarvisEVO

final class UTF8TokenAccumulatorTests: XCTestCase {
    func testEverySplitOfValidUnicodePreservesScalars() {
        let expected = "ASCII café 日本語 🦉 e\u{301}"
        let bytes = Array(expected.utf8)
        for split in 0...bytes.count {
            var decoder = UTF8TokenAccumulator()
            var result = decoder.append(Array(bytes[..<split])) ?? ""
            XCTAssertLessThanOrEqual(decoder.pendingByteCount, 3)
            result += decoder.append(Array(bytes[split...])) ?? ""
            result += decoder.finish()
            XCTAssertEqual(result, expected)
        }
    }
    func testByteByByteValidUnicodeDoesNotInsertReplacement() {
        let expected = "🦉日本語é"
        var decoder = UTF8TokenAccumulator()
        var result = ""
        for byte in expected.utf8 {
            result += decoder.append([byte]) ?? ""
            XCTAssertLessThanOrEqual(decoder.pendingByteCount, 3)
        }
        XCTAssertEqual(result + decoder.finish(), expected)
    }
    func testASCIIBeforeIncompleteScalarIsEmittedImmediately() {
        var decoder = UTF8TokenAccumulator()
        XCTAssertEqual(decoder.append([65, 0xe2, 0x82]), "A")
        XCTAssertEqual(decoder.pendingByteCount, 2)
        XCTAssertEqual(decoder.append([0xac]), "€")
        XCTAssertEqual(decoder.pendingByteCount, 0)
    }
    func testInvalidByteDoesNotWithholdFollowingValidText() {
        var decoder = UTF8TokenAccumulator()
        XCTAssertEqual(decoder.append([0xff, 65, 66]), "�AB")
        XCTAssertEqual(decoder.pendingByteCount, 0)
        XCTAssertEqual(decoder.append([67]), "C")
    }
    func testInvalidEncodingsUseStandardReplacementAcrossEverySplit() {
        let fixtures: [[UInt8]] = [[0xc0, 0xaf], [0xe0, 0x80, 0x80], [0xed, 0xa0, 0x80],
                                  [0xf4, 0x90, 0x80, 0x80], [0xf5, 0x80, 0x80, 0x80],
                                  [0xe2, 0x82, 65], [0x80, 0xbf, 65], [0xf0, 0x90, 0x80, 65]]
        for bytes in fixtures {
            for split in 0...bytes.count {
                var decoder = UTF8TokenAccumulator()
                let first = decoder.append(Array(bytes[..<split])) ?? ""
                let second = decoder.append(Array(bytes[split...])) ?? ""
                XCTAssertEqual(first + second + decoder.finish(), String(decoding: bytes, as: UTF8.self))
                XCTAssertEqual(decoder.pendingByteCount, 0)
            }
        }
    }
    func testEmptyAppendKeepsIncompletePrefixAndFinishFlushesOnce() {
        var decoder = UTF8TokenAccumulator()
        XCTAssertNil(decoder.append([0xf0, 0x9f]))
        XCTAssertNil(decoder.append([]))
        XCTAssertEqual(decoder.pendingByteCount, 2)
        XCTAssertEqual(decoder.finish(), "�")
        XCTAssertEqual(decoder.finish(), "")
        XCTAssertEqual(decoder.pendingByteCount, 0)
    }
    func testRepeatedInvalidBytesNeverAccumulate() {
        var decoder = UTF8TokenAccumulator()
        for _ in 0..<1000 {
            XCTAssertEqual(decoder.append([0xff]), "�")
            XCTAssertEqual(decoder.pendingByteCount, 0)
        }
    }
    func testKnownInvalidPrefixEmitsWhileValidIncompleteTailIsRetained() {
        var decoder = UTF8TokenAccumulator()
        XCTAssertEqual(decoder.append([0xed, 0xa0, 0x80, 65, 0xf0, 0x9f, 0xa6]), "���A")
        XCTAssertEqual(decoder.pendingByteCount, 3)
        XCTAssertEqual(decoder.append([0x89]), "🦉")
    }
}
