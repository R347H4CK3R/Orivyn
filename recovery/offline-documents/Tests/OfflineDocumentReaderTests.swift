import XCTest
@testable import JarvisEVO

/// These are native XCTest sources, NOT claimed run on the Linux authoring host.
final class OfflineDocumentReaderTests: XCTestCase {
    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: nil, subdirectory: "OfficeFixtures"))
    }
    private func read(_ name: String, limits: OfflineDocumentLimits = .standard) throws -> OfflineDocumentResult {
        try OfflineDocumentReader(limits: limits).read(at: fixture(name))
    }
    func testDOCXParagraphsUnicodeTabsBreaksAndTables() throws {
        let result = try read("paragraphs-tables.docx")
        XCTAssertTrue(result.text.contains("Hello café\t世界\nNext line"))
        XCTAssertTrue(result.text.contains("Fruit | Count"))
        XCTAssertTrue(result.text.contains("Kiwi | 4"))
        XCTAssertFalse(result.text.contains("deleted secret"))
        XCTAssertTrue(result.modelContext.contains("Text only"))
        XCTAssertTrue(result.modelContext.contains("not executed"))
        XCTAssertFalse(result.wasTruncated)
    }
    func testXLSXTypesSparseCoordinatesAndRichStrings() throws {
        let r = try read("types-and-formulas.xlsx")
        for expected in ["Worksheet: Sales", "A1=Total revenue", "C1=USD", "A2=42.50", "B2=TRUE", "C2=[error: #DIV/0!]", "D2=2026-11-12T00:00:00Z", "[cached formula value: 42.50]", "[formula cache unavailable]", "serial 60", "1900", "format yyyy-mm-dd", "Worksheet: Hidden sheet (hidden)", "Hidden data"] {
            XCTAssertTrue(r.text.contains(expected), "Missing: \(expected)")
        }
        XCTAssertFalse(r.text.contains("phonetic ignored"))
        XCTAssertFalse(r.text.contains("SUM("))
        XCTAssertTrue(r.modelContext.contains("cached"))
    }
    func testNamespaceAliasesRootedOPCTargetsAndSignedDescriptors() throws {
        XCTAssertTrue(try read("namespace-alias.xlsx").text.contains("Worksheet: Alias"))
        XCTAssertTrue(try read("rooted-target.xlsx").text.contains("Worksheet: Sales"))
        XCTAssertTrue(try read("signed-descriptors.docx").text.contains("Hello café"))
    }
    func testSpreadsheetEscapesDefaultStyleAndTypedFormulaCaches() throws {
        let escaped = try read("escaped-strings.xlsx")
        XCTAssertTrue(escaped.text.contains("line\\rbreak _x0041_ 😀"))
        XCTAssertThrowsError(try read("invalid-surrogate.xlsx"))
        XCTAssertTrue(try read("default-style.xlsx").text.contains("A1=1"))
        let cached = try read("cache-types.xlsx")
        for value in ["A1=[cached formula value: ]", "B1=[formula cache unavailable]", "C1=[cached formula value: FALSE]", "D1=[cached formula value: [error: #DIV/0!]]", "E1=[cached formula value: 2026-11-12", "F1=[formula cache unavailable]", "G1=[formula cache unavailable]"] {
            XCTAssertTrue(cached.text.contains(value),value)
        }
    }
    func test1904DateEpochIsExplicitRatherThanGuessed() throws {
        XCTAssertTrue(try read("date1904.xlsx").text.contains("1904"))
    }
    func testCSVQuotedCommaNewlineEscapedQuoteAndTrailingEmpty() throws {
        let r = try read("structured.csv")
        XCTAssertTrue(r.text.contains("Row 2: A=kiwi | B=4 | C=a,b"))
        XCTAssertTrue(r.text.contains("line one\\nline two"))
        XCTAssertTrue(r.text.contains("a\"b"))
        XCTAssertTrue(r.text.contains("C="))
        XCTAssertTrue(r.modelContext.contains("not executed"))
    }
    func testTSV() throws { XCTAssertTrue(try read("structured.tsv").text.contains("A=kiwi | B=4")) }
    func testRejectsMalformedCSV() throws { XCTAssertThrowsError(try read("bad.csv"))
        for name in ["not-utf8.csv", "quote-in-bare.csv", "junk-after-quote.csv"] { XCTAssertThrowsError(try read(name),name) }
    }
    func testRejectsEmptyDOCXText() throws { XCTAssertThrowsError(try read("empty.docx")) }
    func testRejectsArchiveAttackFixtures() throws {
        for name in ["duplicate.docx", "case-collision.docx", "traversal.docx", "absolute.docx", "backslash.docx", "percent.docx", "encrypted.docx", "symlink.docx", "truncated.docx", "bad-crc.docx", "forged-small-size.docx", "bomb.docx", "header-mismatch.docx", "overlap.docx", "zip64.docx", "unsupported-method.docx"] {
            XCTAssertThrowsError(try read(name), name)
        }
    }
    func testRejectsEntityDepthMalformedXMLAndMacros() throws {
        for name in ["entity.docx", "depth.docx", "malformed-xml.docx", "macro.docx", "utf16-xml.docx", "long-string.docx"] { XCTAssertThrowsError(try read(name), name) }
    }
    func testRejectsRelationshipAndSpreadsheetAttacks() throws {
        for name in ["relationship-traversal.xlsx", "external-worksheet.xlsx", "duplicate-relationship.xlsx", "bad-shared-index.xlsx", "bad-coordinate.xlsx", "unknown-cell.xlsx", "bad-date.xlsx", "nonfinite.xlsx", "duplicate-row.xlsx", "namespace-spoof.xlsx"] { XCTAssertThrowsError(try read(name), name) }
    }
    func testEntryAndStreamAndXMLBudgets() throws {
        var l = OfflineDocumentLimits.standard; l.maximumEntries = 2
        XCTAssertThrowsError(try read("paragraphs-tables.docx", limits: l))
        l = .standard; l.maximumEntryBytes = 100
        XCTAssertThrowsError(try read("paragraphs-tables.docx", limits: l))
        l = .standard; l.maximumExpandedBytes = 100
        XCTAssertThrowsError(try read("paragraphs-tables.docx", limits: l))
        l = .standard; l.maximumXMLNodes = 4
        XCTAssertThrowsError(try read("paragraphs-tables.docx", limits: l))
        l = .standard; l.maximumXMLTextBytes = 4
        XCTAssertThrowsError(try read("paragraphs-tables.docx", limits: l))
        l = .standard; l.maximumSharedStrings = 0
        XCTAssertThrowsError(try read("types-and-formulas.xlsx", limits: l))
    }
    func testBoundedOutputAndRowCellNotices() throws {
        var l = OfflineDocumentLimits.standard; l.maximumOutputCharacters = 40
        let text = try read("paragraphs-tables.docx", limits: l)
        XCTAssertTrue(text.wasTruncated); XCTAssertLessThanOrEqual(text.text.count, 40)
        XCTAssertTrue(text.modelContext.contains("truncated"))
        l = .standard; l.maximumRows = 1
        XCTAssertTrue(try read("types-and-formulas.xlsx", limits: l).wasTruncated)
        l = .standard; l.maximumCells = 1
        XCTAssertTrue(try read("types-and-formulas.xlsx", limits: l).wasTruncated)
    }
    func testRejectsOldBinaryAndArbitraryZIPFormats() throws {
        XCTAssertNil(OfflineDocumentFormat(filenameExtension: "doc"))
        XCTAssertNil(OfflineDocumentFormat(filenameExtension: "xls"))
        XCTAssertNil(OfflineDocumentFormat(filenameExtension: "zip"))
    }
    func testOriginalBytesUnchanged() throws {
        let url = try fixture("paragraphs-tables.docx"); let before = try Data(contentsOf: url)
        _ = try OfflineDocumentReader().read(at: url)
        XCTAssertEqual(try Data(contentsOf: url), before)
    }
    func testRejectsSourceSymlink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let link = root.appendingPathComponent("link.docx")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture("paragraphs-tables.docx"))
        XCTAssertThrowsError(try OfflineDocumentReader().read(at: link))
    }
}
