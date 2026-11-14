import XCTest
@testable import JarvisEVO

final class RuntimeDiagnosticsTests: XCTestCase {
    func testOnlyChangedStateAddsEventAndLogIsBounded() {
        var log = RuntimeDiagnosticLog()
        var state = RuntimeDiagnosticState()
        log.observe(state, at: Date(timeIntervalSince1970: 1))
        log.observe(state, at: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(log.events.count, 1)
        XCTAssertEqual(log.lastChecked, Date(timeIntervalSince1970: 2))
        XCTAssertEqual(log.lastChanged, Date(timeIntervalSince1970: 1))
        for index in 1...250 {
            state.generatedCharacters = index
            log.observe(state, at: Date(timeIntervalSince1970: Double(index + 2)))
        }
        XCTAssertEqual(log.events.count, 200)
        XCTAssertEqual(log.events.last?.state.generatedCharacters, 250)
    }
}
