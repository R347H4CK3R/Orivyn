import XCTest
@testable import JarvisEVO

@MainActor
final class ArchiveRestoreLifetimeTests: XCTestCase {
    func testCapturedLifetimeRevocationSurvivesReplacement() async {
        let captured = ArchiveRestoreLifetime()
        XCTAssertTrue(captured.isValid)
        captured.invalidate()
        let replacement = ArchiveRestoreLifetime()
        XCTAssertFalse(captured.isValid)
        XCTAssertTrue(replacement.isValid)
        XCTAssertFalse(captured === replacement)
    }
    func testRepeatedInvalidationNeverReauthorizesCallback() async {
        let captured = ArchiveRestoreLifetime()
        captured.invalidate(); captured.invalidate()
        XCTAssertFalse(captured.isValid)
    }
}
