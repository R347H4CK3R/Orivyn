#if DEBUG
import XCTest
@testable import JarvisEVO

final class RootFixtureAvailabilityTests: XCTestCase {
    @MainActor func testControlledRootFixtureRequiresBothFlagsAndAnExplicitKnownMode() {
        XCTAssertNil(RootViewRegressionFixtureHost.resolveMode(arguments: []))
        XCTAssertNil(RootViewRegressionFixtureHost.resolveMode(arguments: ["--uitesting"]))
        XCTAssertNil(RootViewRegressionFixtureHost.resolveMode(arguments: ["--root-view-fixture", "voice-ownership"]))
        XCTAssertNil(RootViewRegressionFixtureHost.resolveMode(arguments: ["--uitesting", "--root-view-fixture"]))
        XCTAssertNil(RootViewRegressionFixtureHost.resolveMode(arguments: ["--uitesting", "--root-view-fixture", "unknown"]))
        for mode in ["voice-ownership", "history-scroll", "model-download", "unavailable-provider", "chat-local-tasks", "plugin-suggestion"] {
            XCTAssertEqual(RootViewRegressionFixtureHost.resolveMode(arguments: ["--uitesting", "--root-view-fixture", mode]), mode)
        }
    }
}
#endif
