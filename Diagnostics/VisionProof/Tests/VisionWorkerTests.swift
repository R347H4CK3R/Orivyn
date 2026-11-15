import XCTest
@testable import VisionProof

@MainActor
final class VisionWorkerTests: XCTestCase {
    private var image: OwnedRGB { OwnedRGB(width: 2, height: 1, bytes: Data([255, 0, 0, 255, 255, 255])) }
    func testMissingModelStatusAndReleasePreserved() async throws {
        let worker = try VisionWorker()
        let result = await worker.run(image: image, question: "Describe this image.", model: "/nonexistent/model", projector: "/nonexistent/projector")
        XCTAssertEqual(result.status, 3)
        XCTAssertEqual(result.report.status, 3)
        XCTAssertEqual(result.report.live_resources, 0)
        XCTAssertTrue(result.output.isEmpty)
        await worker.close()
        XCTAssertTrue(worker.isClosed)
    }
    func testPreCancelAndCloseAreLatched() async throws {
        let worker = try VisionWorker()
        worker.cancel()
        let result = await worker.run(image: image, question: "Describe this image.", model: "/nonexistent/model", projector: "/nonexistent/projector")
        XCTAssertEqual(result.status, 2)
        XCTAssertEqual(result.report.live_resources, 0)
        await worker.close(); await worker.close()
        let late = await worker.run(image: image, question: "Describe this image.", model: "", projector: "")
        XCTAssertEqual(late.status, 7)
    }
    func testQuestionAndRGBValidationAreNotMasked() async throws {
        for question in ["", "x\0y", String(repeating: "a", count: 4097), "<|im_start|>"] {
            let worker = try VisionWorker()
            let result = await worker.run(image: image, question: question, model: "/missing", projector: "/missing")
            XCTAssertEqual(result.status, 1)
            XCTAssertEqual(result.report.live_resources, 0)
            await worker.close()
        }
        let worker = try VisionWorker()
        let result = await worker.run(image: OwnedRGB(width: 513, height: 1, bytes: Data(repeating: 0, count: 1539)), question: "Describe.", model: "/missing", projector: "/missing")
        XCTAssertEqual(result.status, 1); await worker.close()
    }
    func testClosedBeforeRunNeverEntersBridge() async throws {
        let worker = try VisionWorker(); await worker.close()
        let result = await worker.run(image: image, question: "Describe.", model: "", projector: "")
        XCTAssertEqual(result.status, 7); XCTAssertTrue(worker.isClosed)
    }
}
