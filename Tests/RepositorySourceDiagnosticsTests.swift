import XCTest
@testable import JarvisEVO

final class RepositorySourceDiagnosticsTests: XCTestCase {
    func testHintsAreBoundedAndDoNotClaimCompilationOrBugProof() {
        let source = "let x = try! decode()\n// TODO review\nfatalError(\"stop\")"
        let hints = RepositorySourceDiagnostics.inspect(path: "App.swift", text: source)
        XCTAssertEqual(hints.map(\.line), [1, 2, 3])
        XCTAssertTrue(hints[0].explanation.contains("not proof"))
        XCTAssertEqual(RepositorySourceDiagnostics.inspect(path: "README.md", text: source).count, 0)
        XCTAssertEqual(RepositorySourceDiagnostics.inspect(path: "App.swift", text: String(repeating: "TODO\n", count: 500)).count, 100)
        XCTAssertEqual(RepositorySourceDiagnostics.inspect(path: "App.swift", text: String(repeating: "x", count: 131_073)).count, 0)
    }
}
