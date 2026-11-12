import XCTest
import Darwin
@testable import JarvisEVO

/// Review-round regression sources. Native compilation/execution remains mandatory.
final class OfficeReviewRegressionTests: XCTestCase {
    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: name,withExtension: nil,subdirectory: "OfficeFixtures"))
    }
    private func read(_ name: String, limits: OfflineDocumentLimits = .standard) throws -> OfflineDocumentResult {
        try OfflineDocumentReader(limits: limits).read(at: fixture(name))
    }
    private func expectStage(_ name: String,_ expected: OfficeValidationStage,limits: OfflineDocumentLimits = .standard) throws {
        do { _ = try read(name,limits: limits); XCTFail("Expected \(expected) from \(name)") }
        catch let error as OfflineDocumentError {
            guard case .rejectedAt(let stage) = error else { return XCTFail("Wrong error for \(name): \(error)") }
            XCTAssertEqual(stage,expected,name)
        }
    }
    func testRepeatedLargeSharedStringsHaveBoundedRenderedUTF8IncludingLabelsAndEscapes() throws {
        var limits = OfflineDocumentLimits.standard
        limits.maximumOutputBytes = 4_096
        let result = try read("repeated-large-shared.xlsx",limits: limits)
        XCTAssertLessThanOrEqual(result.text.utf8.count,limits.maximumOutputBytes)
        XCTAssertLessThanOrEqual(result.text.count,limits.maximumOutputCharacters)
        XCTAssertTrue(result.wasTruncated)
        XCTAssertTrue(result.text.hasPrefix("Worksheet:"))
        XCTAssertTrue(result.text.contains("Row 1: A1="))
    }
    func testCombiningMarksAndEmojiAreUTF8BoundedForEveryFormat() throws {
        var limits = OfflineDocumentLimits.standard
        limits.maximumOutputBytes = 97
        for name in ["repeated-combining.xlsx","combining.docx","combining.csv"] {
            let result = try read(name,limits: limits)
            XCTAssertLessThanOrEqual(result.text.utf8.count,97,name)
            XCTAssertTrue(result.wasTruncated,name)
            XCTAssertEqual(String(data: Data(result.text.utf8),encoding: .utf8),result.text)
        }
        var sink = OfficeTextOutput(limits: limits)
        sink.appendEscaped("\n\t|\\" + String(repeating: "😀",count: 100))
        XCTAssertLessThanOrEqual(sink.text.utf8.count,97)
        XCTAssertTrue(sink.truncated)
        XCTAssertTrue(sink.text.hasPrefix("\\n\\t\\|\\\\"))
    }
    func testFillingSinkSealsItAndDoesNotAppendLaterLabels() {
        var limits = OfflineDocumentLimits.standard; limits.maximumOutputBytes = 5
        var sink = OfficeTextOutput(limits: limits)
        sink.append("abc😀")
        sink.append("SHOULD NOT APPEAR")
        XCTAssertEqual(sink.text,"abc"); XCTAssertTrue(sink.truncated)
    }
    func testOutputSaturationDoesNotSkipRemainingInputValidation() throws {
        var limits = OfflineDocumentLimits.standard; limits.maximumOutputBytes = 97
        do { _ = try read("invalid-after-cap.xlsx",limits: limits); XCTFail("Late invalid shared string was skipped") }
        catch OfflineDocumentError.invalidPackage { }
        do { _ = try read("invalid-after-cap.csv",limits: limits); XCTFail("Late invalid quote was skipped") }
        catch OfflineDocumentError.invalidDelimitedText { }
    }
    func testRepeatedSharedStringAllocationAndTimeMetrics() throws {
        let data = try Data(contentsOf: fixture("repeated-large-shared.xlsx"))
        let options = XCTMeasureOptions(); options.iterationCount = 3
        measure(metrics: [XCTMemoryMetric(),XCTClockMetric()],options: options) {
            do {
                let result = try OfflineDocumentReader().read(data: data,format: .xlsx)
                XCTAssertLessThanOrEqual(result.text.utf8.count,OfflineDocumentLimits.standard.maximumOutputBytes)
            } catch { XCTFail("Unexpected extraction error: \(error)") }
        }
    }
    func testOmittedAndExplicitStyleZeroAreEquivalentForDatesAndCustomFormats() throws {
        for name in ["style-zero-date.xlsx","style-zero-custom.xlsx"] {
            let result = try read(name)
            let line = try XCTUnwrap(result.text.split(separator: "\n").first(where: { $0.hasPrefix("Row 1:") }))
            let values = line.components(separatedBy: " | ")
            guard values.count == 2 else { XCTFail("Expected two style comparison cells"); continue }
            XCTAssertEqual(values[0].components(separatedBy: "A1=").last,values[1].components(separatedBy: "B1=").last)
            XCTAssertTrue(result.text.contains(name.contains("date") ? "serial 60" : "format yyyy-mm-dd"))
        }
    }
    func testInheritedFormatsAreExplicitlyUnresolvedRatherThanAssumedGeneral() throws {
        let r = try read("inherited-styles.xlsx")
        XCTAssertTrue(r.modelContext.contains("inherited number formats are unresolved"))
        XCTAssertTrue(r.text.contains("A1=60 [inherited number format unresolved"))
        XCTAssertTrue(r.text.contains("B1=60 [serial 60")) // An explicit cell format is still applied.
    }
    func testArrayFollowerCachesAndMissingCachesAreLabeledWithoutExecutingFormula() throws {
        let r = try read("array-formula.xlsx")
        XCTAssertTrue(r.text.contains("A1=[cached formula value: 3]"))
        XCTAssertTrue(r.text.contains("A2=[cached formula value: 4]"))
        XCTAssertTrue(r.text.contains("A3=[formula cache unavailable]"))
        XCTAssertFalse(r.text.contains("SUM("))
        XCTAssertFalse(r.text.contains("Row 2: A2=4"))
    }
    func testFormulaRangeMetadataIsBoundedAndValidated() throws {
        try expectStage("oversized-formula-range.xlsx",.formulaRange)
        try expectStage("too-many-formula-ranges.xlsx",.formulaRange)
        for n in ["bad-formula-range.xlsx","formula-anchor-outside.xlsx"] { XCTAssertThrowsError(try read(n),n) }
        var l = OfflineDocumentLimits.standard; l.maximumFormulaRanges = 0
        try expectStage("array-formula.xlsx",.formulaRange,limits: l)
        l = .standard; l.maximumFormulaComparisons = 1
        try expectStage("array-formula.xlsx",.formulaRange,limits: l)
    }
    func testAdversarialFixturesReachTheirNamedValidationStages() throws {
        for (name,stage) in [("entry-size.docx",OfficeValidationStage.declaredEntryBytes),
                             ("total-size.docx",.declaredTotalBytes),
                             ("bomb.docx",.declaredExpansionRatio),
                             ("overlap.docx",.archiveOverlap),
                             ("forged-small-size.docx",.streamedDeclaredBytes),
                             ("bad-crc.docx",.archiveIntegrity)] {
            try expectStage(name,stage)
        }
    }
    func testCancellationDuringDecompressionAndCellValidationIsDeterministic() async throws {
        let data = try Data(contentsOf: fixture("repeated-large-shared.xlsx"))
        for phase in [OfficeReadPhase.decompressedChunk,.documentCell] {
            let cancelled = await Task.detached {
                let reader = OfflineDocumentReader(control: OfficeReadControl { current in
                    if current == phase { withUnsafeCurrentTask { $0?.cancel() } }
                })
                do { _ = try reader.read(data: data,format: .xlsx); return false }
                catch is CancellationError { return true }
                catch { return false }
            }.value
            XCTAssertTrue(cancelled,"No cancellation at \(phase)")
        }
    }
    func testFIFOIsRejectedWithoutBlockingTheTestProcess() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fifo = root.appendingPathComponent("pipe.docx")
        XCTAssertEqual(mkfifo(fifo.path,0o600),0)
        // Keep a nonblocking RDWR guard open. Even a regressed blocking reader cannot hang this test.
        let guardFD = Darwin.open(fifo.path,O_RDWR | O_NONBLOCK | O_CLOEXEC)
        guard guardFD >= 0 else { return XCTFail("Cannot open nonblocking FIFO guard") }
        defer { if guardFD >= 0 { Darwin.close(guardFD) } }
        XCTAssertThrowsError(try OfflineDocumentReader().read(at: fifo))
    }
    func testLegalXMLDeclarationSpacingAndContentDoNotAffectEncodingDetection() throws {
        for n in ["xml-declaration-spacing.docx","xml-declaration-no-encoding.docx"] {
            XCTAssertTrue(try read(n).text.contains("encoding information"),n)
        }
        XCTAssertThrowsError(try read("xml-declaration-misleading.docx"))
    }
    func testSafeDeflateFlagsAndEmptyAncillaryStreamsRemainBounded() throws {
        for n in ["deflate-level-flags.docx","empty-deflate-part.docx"] {
            XCTAssertTrue(try read(n).text.contains("Hello café"),n)
        }
    }
    func testPrinterSettingsAreInertButMacrosRemainRejected() throws {
        let r = try read("printer-settings.docx")
        XCTAssertTrue(r.text.contains("Hello café"))
        XCTAssertTrue(r.modelContext.contains("Printer settings"))
        XCTAssertThrowsError(try read("macro.docx"))
    }
    func testLibraryProducerExportsHaveUsefulContent() throws {
        XCTAssertTrue(try read("producer-python-docx.docx").text.contains("Library exported paragraph"))
        XCTAssertTrue(try read("producer-openpyxl.xlsx").text.contains("42"))
        XCTAssertTrue(try read("producer-xlsxwriter.xlsx").text.contains("cached formula value: 7"))
    }
}
