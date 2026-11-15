import XCTest
import Darwin
import CryptoKit
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
@testable import VisionProof

@MainActor
final class RealVisionTests: XCTestCase {
    private func pair() throws -> (String, String) {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["VISION_MODEL_DIR"], path.hasPrefix("/") else {
            if env["VISION_REQUIRE_REAL"] == "1" { throw NSError(domain: "Missing required model pair", code: 1) }
            throw XCTSkip("Real model gate not enabled. No vision quality evidence from boundary tests.")
        }
        let artifacts: [(String, Int, String)] = [
            ("SmolVLM-500M-Instruct-Q8_0.gguf", 436806912, "9d4612de6a42214499e301494a3ecc2be0abdd9de44e663bda63f1152fad1bf4"),
            ("mmproj-SmolVLM-500M-Instruct-f16.gguf", 199468800, "4b2fca922e549e9b9608f4ba56f93565dd5220e935ba5570a2a864a0fcc988a6")]
        var paths = [String]()
        for (name, size, expected) in artifacts {
            let url = URL(fileURLWithPath: path).appendingPathComponent(name)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            XCTAssertEqual(attributes[.type] as? FileAttributeType, .typeRegular)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  (attributes[.size] as? NSNumber)?.intValue == size else { throw NSError(domain: "Invalid model", code: 1) }
            let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
            var hash = SHA256(); var count = 0
            while let data = try file.read(upToCount: 1_048_576), !data.isEmpty {
                count += data.count; guard count <= size else { throw NSError(domain: "Model grew", code: 1) }
                hash.update(data: data)
            }
            let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
            guard count == size, actual == expected else { throw NSError(domain: "Model hash mismatch", code: 1) }
            paths.append(url.path)
        }
        // CI owns this immutable research directory; no user-selected paths. This
        // test verifier is not the production secure model installation boundary.
        return (paths[0], paths[1])
    }
    private func redCircle() throws -> OwnedRGB {
        let context = try XCTUnwrap(CGContext(data: nil, width: 384, height: 384, bitsPerComponent: 8,
            bytesPerRow: 384 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 384, height: 384))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); context.fillEllipse(in: CGRect(x: 72, y: 72, width: 240, height: 240))
        let png = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let encoded = png as Data
        let attachment = XCTAttachment(data: encoded, uniformTypeIdentifier: UTType.png.identifier)
        attachment.name = "actual-input-pixels"; attachment.lifetime = .keepAlways; add(attachment)
        return try ImageBoundary.decode(encoded)
    }
    func testActualRedCircleEncodeDecodeAndOutput() async throws {
        let (model, projector) = try pair()
        let image = try redCircle()
        let worker = try VisionWorker()
        let result = await worker.run(image: image, question: "Describe the image briefly.", model: model, projector: projector)
        await worker.close()
        let evidence = XCTAttachment(string: "status=\(result.status) positions=\(result.report.positions) chunks=\(result.report.image_chunks) tokens=\(result.report.tokens) resources=\(result.report.live_resources)\n\(result.text ?? "INVALID UTF8")")
        evidence.name = "actual-model-output"; evidence.lifetime = .keepAlways; add(evidence)
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.report.image_chunks, 1)
        XCTAssertGreaterThan(result.report.positions, 0)
        XCTAssertEqual(result.report.live_resources, 0)
        XCTAssertTrue(worker.isClosed)
        let text = try XCTUnwrap(result.text).lowercased()
        XCTAssertTrue(text.contains("red"), text)
        XCTAssertTrue(text.contains("circle"), text)
    }
    func testOwnedWorkerCancelCloseWaitsAndRejectsOverlap() async throws {
        let (model, projector) = try pair()
        let image = try redCircle()
        let worker = try VisionWorker()
        let running = Task { await worker.run(image: image, question: "Describe the image briefly.", model: model, projector: projector) }
        for _ in 0..<100 {
            if worker.isRunning { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(worker.isRunning)
        let overlap = await worker.run(image: image, question: "Describe.", model: model, projector: projector)
        XCTAssertEqual(overlap.status, 7)
        worker.cancel()
        await worker.close()
        let result = await running.value
        XCTAssertEqual(result.status, 2)
        XCTAssertEqual(result.report.live_resources, 0)
        XCTAssertEqual(ov_live_resources(), 0)
        XCTAssertTrue(worker.isClosed)
        XCTAssertTrue(result.output.isEmpty)
    }
    func testNativeEncodeAndDecodeCancellationRelease() throws {
        let (model, projector) = try pair()
        let image = try redCircle()
        for phase: Int32 in [1, 3, 5] {
            let session = try XCTUnwrap(ov_create()); defer { ov_destroy(session) }
            ov_test_cancel_at(session, phase)
            var report = ov_report(); var output = [CChar](repeating: 0, count: 16384)
            let status = model.withCString { m in projector.withCString { p in
                "Describe the image briefly.".withCString { q in image.bytes.withUnsafeBytes { bytes in
                    var request = ov_request(model: m, projector: p, rgb: bytes.baseAddress!.assumingMemoryBound(to: UInt8.self),
                        rgb_bytes: bytes.count, width: UInt32(image.width), height: UInt32(image.height), question: q,
                        question_bytes: strlen(q), context: 2048, output_tokens: 128)
                    return ov_run(session, &request, &output, 16384, &report)
                }}
            }}
            XCTAssertEqual(status, 2); XCTAssertEqual(report.phase, phase)
            XCTAssertGreaterThan(report.callback_count, 0)
            XCTAssertEqual(report.live_resources, 0); XCTAssertEqual(ov_live_resources(), 0)
            XCTAssertEqual(output[0], 0)
        }
    }
}
