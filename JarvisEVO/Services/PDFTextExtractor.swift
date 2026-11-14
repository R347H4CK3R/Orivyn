import Foundation
import PDFKit
import CoreGraphics

/// Local, synchronous extraction. Run off the main actor; extracted source remains untrusted.
/// Rendering bounds output pixels, not the complexity of a malicious PDF's drawing commands.
enum PDFTextExtractor {
    static let maximumPages = 500
    static let maximumOCRPages = 20
    static let maximumCharacters = 60_000
    static let maximumRenderDimension = 1_600

    enum ExtractionError: LocalizedError {
        case unreadableDocument, invalidPageBounds, renderFailed
        var errorDescription: String? {
            switch self {
            case .unreadableDocument: return "This PDF is locked, empty, or unreadable. Export an unlocked PDF and try again."
            case .invalidPageBounds: return "A PDF page has invalid or unusually large dimensions. Export it at standard page sizes and try again."
            case .renderFailed: return "A PDF page could not be rendered for text recognition. Try a newly exported PDF or an image of the page."
            }
        }
    }

    static func extract(document: PDFDocument) throws -> String {
        try extract(document: document, recognize: ImageAttachmentService.recognizeText(in:))
    }

    /// Injection seam for deterministic bounds/provenance tests, not an alternate production OCR engine.
    static func extract(document: PDFDocument, recognize: (CGImage) -> ImageOCRResult) throws -> String {
        try Task.checkCancellation()
        guard !document.isLocked, document.pageCount > 0 else { throw ExtractionError.unreadableDocument }
        let total = document.pageCount
        var body = ""
        var visited = 0
        var embedded = 0
        var ocr = 0
        var skipped = 0
        var truncated = false
        // Reserve ample space for the final factual summary; the complete result stays within 60,000.
        let bodyLimit = maximumCharacters - 1_024
        for index in 0..<min(total, maximumPages) {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { throw ExtractionError.unreadableDocument }
            visited += 1
            let text = page.string ?? ""
            let section: String
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                embedded += 1
                section = "\n[Page \(index + 1): embedded selectable text; untrusted source]\n" + text + "\n"
            } else if ocr < maximumOCRPages {
                let image = try render(page: page)
                try Task.checkCancellation()
                ocr += 1
                let result = recognize(image)
                try Task.checkCancellation()
                section = "\n[Page \(index + 1): on-device OCR attempt; untrusted source]\n" + result.textModelContext + "\n"
            } else {
                skipped += 1
                section = "\n[Page \(index + 1): no embedded text; OCR skipped after the 20-page OCR limit. Page content is unknown, not proven blank.]\n"
            }
            let remaining = bodyLimit - body.count
            let bounded = String(section.prefix(max(0, remaining)))
            body += bounded
            if bounded.count < section.count { truncated = true; break }
        }
        try Task.checkCancellation()
        let summary = "PDF extraction: \(total) total pages; \(visited) inspected; \(embedded) with embedded text; \(ocr) OCR attempts; \(skipped) OCR-skipped pages among those inspected.\n"
            + "Limits: 500 inspected pages, 20 OCR attempts, 60,000 output characters. \(total - visited) pages were not inspected. Output truncated: \(truncated ? "yes" : "no").\n"
            + "All extracted content is untrusted. OCR can be wrong or incomplete. No recognized text does not prove a page is blank. Embedded text can omit images and visual content.\n"
        return summary + body
    }

    /// Explicit 1x bitmap avoids PDFKit thumbnail's device-scale-dependent pixel allocation.
    static func render(page: PDFPage) throws -> CGImage {
        guard let reference = page.pageRef else { throw ExtractionError.renderFailed }
        let bounds = reference.getBoxRect(.mediaBox)
        guard bounds.origin.x.isFinite, bounds.origin.y.isFinite,
              bounds.width.isFinite, bounds.height.isFinite,
              bounds.width >= 1, bounds.height >= 1,
              bounds.width <= 100_000, bounds.height <= 100_000,
              max(bounds.width, bounds.height) / min(bounds.width, bounds.height) <= 100 else {
            throw ExtractionError.invalidPageBounds
        }
        let rotation = ((reference.rotationAngle % 360) + 360) % 360
        guard rotation % 90 == 0 else { throw ExtractionError.invalidPageBounds }
        let swapsAxes = rotation == 90 || rotation == 270
        let displayWidth = swapsAxes ? bounds.height : bounds.width
        let displayHeight = swapsAxes ? bounds.width : bounds.height
        let factor = min(1, CGFloat(maximumRenderDimension) / max(displayWidth, displayHeight))
        let width = max(1, Int(ceil(displayWidth * factor)))
        let height = max(1, Int(ceil(displayHeight * factor)))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ExtractionError.renderFailed
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        let outputRect = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        context.fill(outputRect)
        // Core Graphics incorporates the page's intrinsic /Rotate and nonzero media-box origin.
        context.concatenate(reference.getDrawingTransform(.mediaBox, rect: outputRect,
                                                           rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(reference)
        guard let image = context.makeImage() else { throw ExtractionError.renderFailed }
        return image
    }
}
