import XCTest
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import JarvisEVO

/// Explicit opt-in simulator smoke: one real model, one generated image, no tools.
/// Missing prerequisites FAIL when ORIVYN_REQUIRE_PRODUCTION_VISION=1.
@MainActor
final class ProductionVisionRuntimeTests: XCTestCase {
    private func redSquarePNG() throws -> Data {
        let side = 384
        var rgba = [UInt8](repeating: 255, count: side * side * 4)
        for y in 72..<312 {
            for x in 72..<312 {
                let offset = (y * side + x) * 4
                rgba[offset + 1] = 0; rgba[offset + 2] = 0
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(rgba) as CFData))
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let image = try XCTUnwrap(CGImage(width: side, height: side, bitsPerComponent: 8,
            bitsPerPixel: 32, bytesPerRow: side * 4, space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let bytes = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return bytes as Data
    }

    func testRequiredProductionPNGInferenceAndRelease() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["ORIVYN_REQUIRE_PRODUCTION_VISION"] == "1" else {
            throw XCTSkip("Opt-in real production vision smoke is not enabled; no inference pass is claimed.")
        }
        #if !ORIVYN_NATIVE_VISION
        XCTFail("Required vision gate needs ORIVYN_NATIVE_VISION and the combined framework in app AND test targets.")
        #elseif !targetEnvironment(simulator)
        XCTFail("This gate requires an iOS simulator and its dedicated host fixture directory; it is not a device gate.")
        #else
        guard let path = environment["ORIVYN_VISION_MODEL_DIR"], path.hasPrefix("/"), !path.utf8.contains(0) else {
            XCTFail("Required absolute ORIVYN_VISION_MODEL_DIR is missing or invalid."); return
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        let attributes = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard attributes.isDirectory == true, attributes.isSymbolicLink != true else {
            XCTFail("Required fixture directory must be an owned regular directory, not a symlink."); return
        }
        // Actual production file store: no fake verified paths or substituted hash
        // checker. Both full pinned hashes are verified inside runtime acquisition.
        // Dedicated fixture root may receive the store's backup-exclusion metadata.
        let store = VisionPairStore(files: try VisionModelStorage(root: directory))
        let png = try redSquarePNG()
        let input = XCTAttachment(data: png, uniformTypeIdentifier: UTType.png.identifier)
        input.name = "actual-production-vision-input"; input.lifetime = .keepAlways; add(input)
        // Production ImageIO/white composite/packed-RGB boundary, not Linux RGB shim.
        let prepared = try ImageBoundary.decode(png)
        XCTAssertEqual(prepared.width, 384); XCTAssertEqual(prepared.height, 384)
        XCTAssertEqual(prepared.bytes.count, 384 * 384 * 3)
        guard prepared.width == 384, prepared.height == 384, prepared.bytes.count == 384 * 384 * 3 else { return }
        let center = (192 * 384 + 192) * 3
        XCTAssertGreaterThan(prepared.bytes[center], 250)
        XCTAssertLessThan(prepared.bytes[center + 1], 5)
        XCTAssertLessThan(prepared.bytes[center + 2], 5)

        let runtime = try NativeVisionRuntime(store: store)
        let start = Date()
        let answer: String
        do {
            answer = try await runtime.run(encodedImage: png,
                question: "Describe the visible image in one sentence.")
        } catch {
            runtime.cancel()
            let released = await runtime.close()
            XCTAssertTrue(released, "Failure path must acknowledge native resource teardown")
            throw error
        }
        let released = await runtime.close()
        XCTAssertTrue(released)
        let evidence = XCTAttachment(string: "scope=iOS simulator CPU production runtime smoke\nmodelRevision=\(VisionModelPair.revision)\nmodelSHA256=\(VisionModelPair.model.sha256)\nprojectorSHA256=\(VisionModelPair.projector.sha256)\nelapsedSeconds=\(Date().timeIntervalSince(start))\ncloseAcknowledged=\(released)\nactualAnswer=\(answer)")
        evidence.name = "actual-production-vision-result"; evidence.lifetime = .keepAlways; add(evidence)
        XCTAssertTrue(answer.lowercased().contains("red"), answer)
        XCTAssertTrue(answer.lowercased().contains("square"), answer)
        // Verify the actual pair lease was released, using real file verification.
        // This is not a second model load and does not claim a heap-leak test.
        let nextLease = try await store.acquire()
        await store.release(nextLease)
        // Runner requires this marker in addition to xcodebuild success, so a
        // missing scheme environment cannot turn the required gate into a skip.
        print("ORIVYN_PRODUCTION_VISION_REQUIRED_GATE_COMPLETED")
        #endif
    }
}
