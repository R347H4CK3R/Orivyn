import XCTest
@testable import JarvisEVO

final class ModelDownloadPolicyTests: XCTestCase {
    func testAutomaticWiFiPolicyIsEnforcedBySessionNotOnlyReachability() {
        let configuration = ModelDownloadPolicy.automaticWiFi.configuration()
        XCTAssertFalse(configuration.allowsCellularAccess)
        XCTAssertFalse(configuration.allowsExpensiveNetworkAccess)
        XCTAssertFalse(configuration.allowsConstrainedNetworkAccess)
        XCTAssertFalse(configuration.waitsForConnectivity)
        XCTAssertNil(configuration.urlCache)
    }
    func testExplicitCellularOptInStillRejectsConstrainedNetwork() {
        let configuration = ModelDownloadPolicy.automaticCellular.configuration()
        XCTAssertTrue(configuration.allowsCellularAccess)
        XCTAssertTrue(configuration.allowsExpensiveNetworkAccess)
        XCTAssertFalse(configuration.allowsConstrainedNetworkAccess)
    }
    func testManualDownloadRetainsItsExplicitUserInitiatedNetworkPolicy() {
        let configuration = ModelDownloadPolicy.userInitiated.configuration()
        XCTAssertTrue(configuration.allowsCellularAccess)
        XCTAssertTrue(configuration.allowsExpensiveNetworkAccess)
        XCTAssertTrue(configuration.allowsConstrainedNetworkAccess)
    }
}
