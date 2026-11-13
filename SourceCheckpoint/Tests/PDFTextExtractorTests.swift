import XCTest
import PDFKit
import UIKit
@testable import JarvisEVO

@MainActor
final class PDFTextExtractorTests: XCTestCase {
    private func document(_ texts: [String], size: CGSize = CGSize(width: 300, height: 300)) throws -> PDFDocument {
        let bytes = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size)).pdfData { context in
            for text in texts {
                context.beginPage()
                (text as NSString).draw(at: CGPoint(x: 20, y: 30), withAttributes: [.font: UIFont.systemFont(ofSize: 14)])
            }
        }
        return try XCTUnwrap(PDFDocument(data: bytes))
    }

    func testEmbeddedTextPreservedWithoutOCR() throws {
        var calls = 0
        let output = try PDFTextExtractor.extract(document: document(["Seventeen apples", "Twenty pears"])) { _ in
            calls += 1; return .noTextRecognized
        }
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(output.contains("2 total pages"))
        XCTAssertTrue(output.contains("Seventeen apples"))
        XCTAssertTrue(output.contains("Page 2: embedded selectable text"))
    }

    func testMixedPagesLabelActualOCRAndEmbeddedProvenance() throws {
        var calls = 0
        let output = try PDFTextExtractor.extract(document: document(["Embedded source", ""])) { image in
            calls += 1
            XCTAssertLessThanOrEqual(max(image.width, image.height), 1600)
            return .bounded(lines: ["Injected test recognition, not an accuracy claim"])
        }
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(output.contains("Page 1: embedded selectable text"))
        XCTAssertTrue(output.contains("Page 2: on-device OCR attempt"))
        XCTAssertTrue(output.contains("Injected test recognition"))
    }

    func testNoRecognitionIsNotClaimedBlank() throws {
        let output = try PDFTextExtractor.extract(document: document([""])) { _ in .noTextRecognized }
        XCTAssertTrue(output.contains("does not prove a page is blank"))
        XCTAssertTrue(output.contains("1 OCR attempts"))
    }

    func testOCRUnavailableIsDisclosed() throws {
        let output = try PDFTextExtractor.extract(document: document([""])) { _ in .unavailable }
        XCTAssertTrue(output.contains("could not be completed"))
    }

    func testOCRAttemptLimitPreservesSubsequentEmbeddedText() throws {
        var calls = 0
        let output = try PDFTextExtractor.extract(document: document(Array(repeating: "", count: 21) + ["Last embedded page"])) { _ in
            calls += 1; return .noTextRecognized
        }
        XCTAssertEqual(calls, 20)
        XCTAssertTrue(output.contains("1 OCR-skipped pages"))
        XCTAssertTrue(output.contains("Last embedded page"))
    }

    func testPageLimitDisclosesActualTotal() throws {
        let output = try PDFTextExtractor.extract(document: document(Array(repeating: "x", count: 501))) { _ in .unavailable }
        XCTAssertTrue(output.contains("501 total pages; 500 inspected"))
        XCTAssertTrue(output.contains("1 pages were not inspected"))
    }

    func testOutputBoundAndTruncationDisclosure() throws {
        let output = try PDFTextExtractor.extract(document: document(Array(repeating: "", count: 20))) { _ in
            .bounded(lines: [String(repeating: "x", count: 12_000)])
        }
        XCTAssertLessThanOrEqual(output.count, 60_000)
        XCTAssertTrue(output.contains("Output truncated: yes"))
        XCTAssertTrue(output.contains("pages were not inspected"))
    }

    func testBitmapBoundAndUnsafeGeometry() throws {
        let pdf = try document([""])
        let page = try XCTUnwrap(pdf.page(at: 0))
        page.setBounds(CGRect(x: 0, y: 0, width: 5_000, height: 3_000), for: .mediaBox)
        let validBytes = try XCTUnwrap(pdf.dataRepresentation())
        let validPDF = try XCTUnwrap(PDFDocument(data: validBytes))
        let validPage = try XCTUnwrap(validPDF.page(at: 0))
        let image = try PDFTextExtractor.render(page: validPage)
        XCTAssertLessThanOrEqual(max(image.width, image.height), 1600)
        page.setBounds(CGRect(x: 0, y: 0, width: 100_001, height: 300), for: .mediaBox)
        let invalidBytes = try XCTUnwrap(pdf.dataRepresentation())
        let invalidPDF = try XCTUnwrap(PDFDocument(data: invalidBytes))
        let invalidPage = try XCTUnwrap(invalidPDF.page(at: 0))
        XCTAssertThrowsError(try PDFTextExtractor.render(page: invalidPage))
    }

    func testRasterOnlyPDFUsesRealVisionRecognition() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 300), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1000, height: 300))
            ("ORIVYN 4729" as NSString).draw(at: CGPoint(x: 60, y: 90), withAttributes: [
                .font: UIFont.systemFont(ofSize: 64), .foregroundColor: UIColor.black
            ])
        }
        let pdf = PDFDocument()
        pdf.insert(try XCTUnwrap(PDFPage(image: image)), at: 0)
        let bytes = try XCTUnwrap(pdf.dataRepresentation())
        let serialized = try XCTUnwrap(PDFDocument(data: bytes))
        XCTAssertTrue((serialized.page(at: 0)?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let output = try PDFTextExtractor.extract(document: serialized)
        XCTAssertTrue(output.contains("on-device OCR attempt"))
        XCTAssertTrue(output.contains("4729"), "Real Vision regression: recognition must actually produce the raster text.")
    }

    func testRotatedNonsquareRasterKeepsAllFourCornerMarkers() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 200), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 600, height: 200))
            let markers: [(UIColor, CGRect)] = [
                (.red, CGRect(x: 10, y: 10, width: 30, height: 30)),
                (.green, CGRect(x: 560, y: 10, width: 30, height: 30)),
                (.blue, CGRect(x: 10, y: 160, width: 30, height: 30)),
                (.black, CGRect(x: 560, y: 160, width: 30, height: 30))
            ]
            for (color, rect) in markers { color.setFill(); context.fill(rect) }
        }
        for angle in [90, 270] {
            let document = PDFDocument()
            let page = try XCTUnwrap(PDFPage(image: image))
            page.rotation = angle
            document.insert(page, at: 0)
            let bytes = try XCTUnwrap(document.dataRepresentation())
            let reopened = try XCTUnwrap(PDFDocument(data: bytes))
            let reopenedPage = try XCTUnwrap(reopened.page(at: 0))
            let rendered = try PDFTextExtractor.render(page: reopenedPage)
            XCTAssertLessThan(rendered.width, rendered.height)
            let width = rendered.width, height = rendered.height
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            try pixels.withUnsafeMutableBytes { buffer in
                let bitmap = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
                bitmap.draw(rendered, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            }
            var counts = [0, 0, 0, 0]
            for offset in stride(from: 0, to: pixels.count, by: 4) {
                let r = pixels[offset], g = pixels[offset + 1], b = pixels[offset + 2]
                if r > 180 && g < 80 && b < 80 { counts[0] += 1 }
                if g > 180 && r < 80 && b < 80 { counts[1] += 1 }
                if b > 180 && r < 80 && g < 80 { counts[2] += 1 }
                if r < 80 && g < 80 && b < 80 { counts[3] += 1 }
            }
            for count in counts { XCTAssertGreaterThan(count, 100, "Every corner marker must survive rotation without clipping") }
        }
    }

    func testErrorsOfferActionableRecovery() {
        for error in [PDFTextExtractor.ExtractionError.unreadableDocument, .invalidPageBounds, .renderFailed] {
            XCTAssertFalse(error.localizedDescription.isEmpty)
            XCTAssertTrue(error.localizedDescription.contains("PDF"))
        }
    }

    func testCancelledTaskDoesNotStartExtraction() async throws {
        let task = Task { @MainActor in
            try PDFTextExtractor.extract(document: self.document(["Do not process"]))
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation must propagate") }
        catch is CancellationError { }
        catch { XCTFail("Unexpected error: \(error)") }
    }

    func testEmptyDocumentRejected() {
        XCTAssertThrowsError(try PDFTextExtractor.extract(document: PDFDocument()))
    }
}
