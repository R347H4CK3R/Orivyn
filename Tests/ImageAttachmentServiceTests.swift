import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import JarvisEVO

@MainActor
final class ImageAttachmentServiceTests: XCTestCase {
    private var root: URL!
    private var service: ImageAttachmentService!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        service = try ImageAttachmentService(directory: root.appendingPathComponent("Images", isDirectory: true))
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: root) }

    // Storing picker URLs instead of private copies loses the image when picker access ends.
    func testPNGImportKeepsOriginalBytesAndCreatesIndependentPreview() throws {
        let bytes = try XCTUnwrap(render(size: CGSize(width: 320, height: 180)).pngData())
        let source = try write(bytes, named: "photo.png")
        let result = try service.importFile(at: source)
        let original = try XCTUnwrap(service.url(forRelativePath: result.relativePath))
        let preview = try XCTUnwrap(service.url(forRelativePath: result.previewRelativePath))
        XCTAssertNotEqual(original, source)
        XCTAssertNotEqual(preview, original)
        XCTAssertEqual(result.name, "photo.png")
        XCTAssertEqual(result.mediaType, "image/png")
        XCTAssertEqual(result.byteCount, bytes.count)
        XCTAssertEqual(result.pixelWidth, 320)
        XCTAssertEqual(result.pixelHeight, 180)
        try FileManager.default.removeItem(at: source)
        XCTAssertEqual(try Data(contentsOf: original), bytes)
        let decoded = try XCTUnwrap(UIImage(contentsOfFile: preview.path)?.cgImage)
        XCTAssertEqual(decoded.width, 320)
        XCTAssertEqual(decoded.height, 180)
    }

    // MIME types and storage suffixes must come from the bytes, not the display name.
    func testJPEGWithMisleadingFilenameUsesDetectedFormatAndRandomSafePath() throws {
        let bytes = try XCTUnwrap(render().jpegData(compressionQuality: 0.9))
        let result = try service.importData(bytes, suggestedName: "../../not-really.png")
        XCTAssertEqual(result.mediaType, "image/jpeg")
        XCTAssertEqual(result.name, "not-really.png")
        XCTAssertEqual(result.relativePath, result.id.uuidString + ".jpg")
        XCTAssertEqual(result.previewRelativePath, result.id.uuidString + "-preview.jpg")
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(service.url(forRelativePath: result.relativePath))), bytes)
    }

    func testRepeatedImportsNeverOverwriteEarlierOriginalOrPreview() throws {
        let bytes = try XCTUnwrap(render().pngData())
        let first = try service.importData(bytes, suggestedName: "same.png")
        let second = try service.importData(bytes, suggestedName: "same.png")
        XCTAssertNotEqual(first.relativePath, second.relativePath)
        XCTAssertNotEqual(first.previewRelativePath, second.previewRelativePath)
        XCTAssertEqual(try storedFiles().count, 4)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(service.url(forRelativePath: first.relativePath))), bytes)
    }

    // Reusing source properties would leak GPS/EXIF metadata into the normalized preview.
    func testPreviewAppliesOrientationAndRemovesSourceMetadata() throws {
        let image = try XCTUnwrap(render(size: CGSize(width: 180, height: 90)).cgImage)
        let bytes = try encode(image, type: .jpeg, properties: [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 37.0, kCGImagePropertyGPSLatitudeRef: "N"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:01:02 03:04:05"]
        ])
        let result = try service.importData(bytes, suggestedName: "camera.jpg")
        let original = try XCTUnwrap(service.url(forRelativePath: result.relativePath))
        let preview = try XCTUnwrap(service.url(forRelativePath: result.previewRelativePath))
        let originalProperties = try properties(at: original)
        XCTAssertNotNil(originalProperties[kCGImagePropertyGPSDictionary])
        let previewProperties = try properties(at: preview)
        XCTAssertNil(previewProperties[kCGImagePropertyGPSDictionary])
        let previewEXIF = previewProperties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        XCTAssertNil(previewEXIF?[kCGImagePropertyExifDateTimeOriginal])
        XCTAssertEqual(result.previewPixelWidth, 90)
        XCTAssertEqual(result.previewPixelHeight, 180)
        XCTAssertEqual(try Data(contentsOf: original), bytes, "Sharing the original intentionally preserves original metadata")
    }

    func testLargeButAllowedImageProducesBoundedPreview() throws {
        let bytes = try XCTUnwrap(render(size: CGSize(width: 3000, height: 1500)).pngData())
        let result = try service.importData(bytes, suggestedName: "wide.png")
        XCTAssertEqual(result.pixelWidth, 3000)
        XCTAssertEqual(result.previewPixelWidth, 2048)
        XCTAssertEqual(result.previewPixelHeight, 1024)
        let preview = try XCTUnwrap(UIImage(contentsOfFile: XCTUnwrap(service.url(forRelativePath: result.previewRelativePath)).path)?.cgImage)
        XCTAssertEqual(preview.width, 2048)
        XCTAssertEqual(preview.height, 1024)
    }

    // This exercises Apple's real Vision recognizer, not a mocked OCR success path.
    func testVisionExtractsRenderedWordsForTextOnlyModelContext() throws {
        let bytes = try XCTUnwrap(render(size: CGSize(width: 1400, height: 400), text: "JARVIS EVO\n42 APPLES").pngData())
        let result = try service.importData(bytes, suggestedName: "receipt.png")
        guard case let .recognized(text, isTruncated) = result.ocr else {
            return XCTFail("Vision did not recognize the rendered fixture: \(result.ocr)")
        }
        XCTAssertTrue(text.uppercased().contains("JARVIS"), text)
        XCTAssertTrue(text.uppercased().contains("42 APPLES"), text)
        XCTAssertFalse(isTruncated)
        XCTAssertTrue(result.textModelContext.contains(text))
        XCTAssertTrue(result.textModelContext.contains("OCR"))
        XCTAssertTrue(result.textModelContext.contains("has not received image pixels"))
    }

    func testBlankImageIsStillImportableButDoesNotClaimVisualUnderstanding() throws {
        let result = try service.importData(XCTUnwrap(render().pngData()), suggestedName: "blank.png")
        XCTAssertEqual(result.ocr, .noTextRecognized)
        XCTAssertTrue(result.textModelContext.contains("No readable text was recognized"))
        XCTAssertTrue(result.textModelContext.contains("has not received image pixels"))
        XCTAssertNotNil(service.url(forRelativePath: result.relativePath))
        XCTAssertNotNil(service.url(forRelativePath: result.previewRelativePath))
    }

    // The same production formatter handles Vision's recognized lines and UTF-8-safe limits.
    func testRecognizedTextIsCharacterBoundedAndTruncationIsExplicit() {
        let result = ImageOCRResult.bounded(lines: [String(repeating: "🦉", count: 12_001)])
        guard case let .recognized(text, isTruncated) = result else { return XCTFail("Missing recognized text") }
        XCTAssertEqual(text, String(repeating: "🦉", count: 12_000))
        XCTAssertTrue(isTruncated)
        XCTAssertTrue(result.textModelContext.contains("truncated"))
    }

    func testRecognizedLineLimitDisclosesOmittedLines() {
        let result = ImageOCRResult.bounded(lines: (1...201).map { "Line \($0)" })
        guard case let .recognized(text, isTruncated) = result else { return XCTFail("Missing recognized text") }
        XCTAssertEqual(text.components(separatedBy: "\n").count, 200)
        XCTAssertTrue(text.hasSuffix("Line 200"))
        XCTAssertFalse(text.contains("Line 201"))
        XCTAssertTrue(isTruncated)
    }

    func testOCRFailureContextDoesNotPretendToHaveAnalyzedImage() {
        XCTAssertTrue(ImageOCRResult.unavailable.textModelContext.contains("Text recognition could not be completed"))
        XCTAssertTrue(ImageOCRResult.unavailable.textModelContext.contains("has not received image pixels"))
    }

    func testEmptyAndOversizedInputsAreRejectedWithoutFiles() throws {
        assertRejected(Data(), as: .invalidSize)
        assertRejected(Data(repeating: 0, count: 10 * 1024 * 1024 + 1), as: .invalidSize)
        XCTAssertTrue(try storedFiles().isEmpty)
    }

    func testOversizedFileIsRejectedBeforeLoadingOrCopying() throws {
        let source = try write(Data(repeating: 0, count: 10 * 1024 * 1024 + 1), named: "huge.png")
        XCTAssertThrowsError(try service.importFile(at: source)) { error in
            XCTAssertEqual(error as? ImageAttachmentError, .invalidSize)
        }
        XCTAssertTrue(try storedFiles().isEmpty)
    }

    func testMisnamedTextAndTruncatedPNGAreRejectedWithoutFiles() throws {
        assertRejected(Data("This is text, not a PNG.".utf8), as: .invalidImage)
        let png = try XCTUnwrap(render().pngData())
        assertRejected(Data(png.prefix(24)), as: .invalidImage)
        XCTAssertTrue(try storedFiles().isEmpty)
    }

    func testUnsupportedGIFIsRejectedEvenWithPNGName() throws {
        let image = try XCTUnwrap(render().cgImage)
        assertRejected(try encode(image, type: .gif), as: .unsupportedFormat)
        XCTAssertTrue(try storedFiles().isEmpty)
    }

    func testAnimatedPNGIsRejectedInsteadOfSilentlyAnalyzingOnlyFirstFrame() throws {
        let frame = try XCTUnwrap(render().cgImage)
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 2, nil))
        CGImageDestinationSetProperties(destination, [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: 0]] as CFDictionary)
        let frameProperties = [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGDelayTime: 0.1]] as CFDictionary
        CGImageDestinationAddImage(destination, frame, frameProperties)
        CGImageDestinationAddImage(destination, frame, frameProperties)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let bytes = data as Data
        let source = try XCTUnwrap(CGImageSourceCreateWithData(bytes as CFData, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), 2, "Fixture must really contain multiple frames")
        assertRejected(bytes, as: .multipleFrames)
        XCTAssertTrue(try storedFiles().isEmpty)
    }

    // Updating IHDR and its CRC does not expand the 2x2 IDAT payload. ImageIO rejects this
    // malformed image before exposing dimensions; it cannot establish the pixel-limit branch.
    func testPixelBombHeaderIsRejectedBeforeDecodingOrCopying() throws {
        let png = try XCTUnwrap(render(size: CGSize(width: 2, height: 2)).pngData())
        assertRejected(replacingPNGDimensions(png, width: 10_000, height: 10_000), as: .invalidImage)
        XCTAssertTrue(try storedFiles().isEmpty)
    }

    func testValidImageExceedingTotalPixelCapIsRejectedWithoutCopying() throws {
        // 40,008,000 pixels exceeds the 40 MP limit while both sides remain below 16,384.
        // The complete 1-bit source plane is only 5,001,000 bytes, not a 160 MB RGBA bitmap.
        let png = try monochromePNG(width: 8_000, height: 5_001)
        try assertReadablePNG(png, width: 8_000, height: 5_001)
        assertRejected(png, as: .pixelLimitExceeded)
        XCTAssertTrue(try storedFiles().isEmpty)
    }

    func testExtremeSingleDimensionIsRejectedEvenBelowTotalPixelCap() throws {
        let png = try monochromePNG(width: 16_385, height: 1)
        try assertReadablePNG(png, width: 16_385, height: 1)
        assertRejected(png, as: .pixelLimitExceeded)
        XCTAssertTrue(try storedFiles().isEmpty)
    }

    func testImportRejectsSymlinkAndDirectorySources() throws {
        let source = try write(XCTUnwrap(render().pngData()), named: "original.png")
        let link = root.appendingPathComponent("alias.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        for url in [link, service.directory] {
            XCTAssertThrowsError(try service.importFile(at: url)) { error in
                XCTAssertEqual(error as? ImageAttachmentError, .unsafeFile)
            }
        }
        XCTAssertTrue(try storedFiles().isEmpty)
    }

    func testLookupRejectsTraversalDirectoriesAndSymbolicLinks() throws {
        let source = try write(Data("outside".utf8), named: "outside.jpg")
        let inside = try service.importData(XCTUnwrap(render().pngData()), suggestedName: "safe.png")
        let stored = try XCTUnwrap(service.url(forRelativePath: inside.relativePath))
        try FileManager.default.createSymbolicLink(at: service.directory.appendingPathComponent("external.jpg"), withDestinationURL: source)
        try FileManager.default.createSymbolicLink(at: service.directory.appendingPathComponent("internal.jpg"), withDestinationURL: stored)
        try FileManager.default.createSymbolicLink(at: service.directory.appendingPathComponent("broken.jpg"), withDestinationURL: root.appendingPathComponent("missing.jpg"))
        try FileManager.default.createDirectory(at: service.directory.appendingPathComponent("folder.jpg"), withIntermediateDirectories: false)
        for path in ["", ".", "..", "../outside.jpg", source.path, "a/b.jpg", "a\\b.jpg", "external.jpg", "internal.jpg", "broken.jpg", "folder.jpg"] {
            XCTAssertNil(service.url(forRelativePath: path), path)
        }
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "outside")
    }

    func testSymlinkStorageRootIsRejected() throws {
        let link = root.appendingPathComponent("LinkedImages")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: service.directory)
        XCTAssertThrowsError(try ImageAttachmentService(directory: link)) { error in
            XCTAssertEqual(error as? ImageAttachmentError, .unsafeFile)
        }
    }

    func testMissingStorageFailsInsteadOfReportingImportSuccess() throws {
        try FileManager.default.removeItem(at: service.directory)
        XCTAssertThrowsError(try service.importData(XCTUnwrap(render().pngData()), suggestedName: "photo.png"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: service.directory.path))
    }

    func testCancelledImportLeavesNoFiles() async throws {
        let bytes = try XCTUnwrap(render().pngData())
        let importer = try XCTUnwrap(service)
        let task = Task { try importer.importData(bytes, suggestedName: "cancelled.png") }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("A cancelled import must not report success")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertTrue(try storedFiles().isEmpty)
    }

    private func render(size: CGSize = CGSize(width: 320, height: 180), text: String = "") -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            if !text.isEmpty {
                (text as NSString).draw(in: CGRect(x: 40, y: 40, width: size.width - 80, height: size.height - 80), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 80, weight: .bold), .foregroundColor: UIColor.black
                ])
            }
        }
    }

    private func encode(_ image: CGImage, type: UTType, properties: [CFString: Any] = [:]) throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func properties(at url: URL) throws -> [CFString: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    private func write(_ bytes: Data, named name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try bytes.write(to: url)
        return url
    }

    private func storedFiles() throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: service.directory.path) }

    private func assertRejected(_ bytes: Data, as expected: ImageAttachmentError, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try service.importData(bytes, suggestedName: "input.png"), file: file, line: line) { error in
            XCTAssertEqual(error as? ImageAttachmentError, expected, file: file, line: line)
        }
    }

    private func replacingPNGDimensions(_ original: Data, width: UInt32, height: UInt32) -> Data {
        var bytes = [UInt8](original)
        func put(_ value: UInt32, at offset: Int) {
            for byte in 0..<4 { bytes[offset + byte] = UInt8(truncatingIfNeeded: value >> (24 - 8 * byte)) }
        }
        put(width, at: 16)
        put(height, at: 20)
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes[12..<29] {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xEDB8_8320 : 0) }
        }
        put(crc ^ 0xFFFF_FFFF, at: 29)
        return Data(bytes)
    }

    private func monochromePNG(width: Int, height: Int) throws -> Data {
        let boundedWidth = try XCTUnwrap((1...16_385).contains(width) ? width : nil)
        let boundedHeight = try XCTUnwrap((1...5_001).contains(height) ? height : nil)
        let bytesPerRow = (boundedWidth + 7) / 8
        let byteCount = bytesPerRow * boundedHeight
        let allocation = try XCTUnwrap(byteCount <= 5_100_000 ? byteCount : nil, "Keep fixture allocations bounded")
        var pixels = Data(count: allocation)
        pixels.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
            // Deterministic noise avoids depending on an image decoder accepting an extreme
            // compression ratio. All rows contain real pixels matching the encoded dimensions.
            var state: UInt32 = 0x1357_9BDF
            for index in 0..<buffer.count {
                state ^= state << 13
                state ^= state >> 17
                state ^= state << 5
                buffer[index] = UInt8(truncatingIfNeeded: state)
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: pixels as CFData))
        let image = try XCTUnwrap(CGImage(width: boundedWidth, height: boundedHeight,
            bitsPerComponent: 1, bitsPerPixel: 1, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        return try encode(image, type: .png)
    }

    private func assertReadablePNG(_ bytes: Data, width: Int, height: Int) throws {
        XCTAssertLessThanOrEqual(bytes.count, 10 * 1024 * 1024, "Exercise dimensions, not the encoded-size limit")
        let source = try XCTUnwrap(CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.png.identifier)
        XCTAssertEqual(CGImageSourceGetCount(source), 1)
        let values = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual((values[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue, width)
        XCTAssertEqual((values[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, height)
        XCTAssertEqual(CGImageSourceGetStatus(source), .statusComplete)
        // Check an actual decode before testing the service, without asking for a full-size bitmap.
        let preview = try XCTUnwrap(CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 64,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary))
        XCTAssertGreaterThan(preview.width, 0)
        XCTAssertGreaterThan(preview.height, 0)
        XCTAssertLessThanOrEqual(preview.width, 64)
        XCTAssertLessThanOrEqual(preview.height, 64)
        XCTAssertEqual(CGImageSourceGetStatusAtIndex(source, 0), .statusComplete)
    }
}
