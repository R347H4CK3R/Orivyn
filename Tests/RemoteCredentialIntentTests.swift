import XCTest
@testable import JarvisEVO
final class RemoteCredentialIntentTests: XCTestCase {
    func testKeepMatchingNormalizedEndpointDoesNotWrite() throws {
        XCTAssertNil(try RemoteCredentialIntent.keepExisting.valueToWrite(endpoint: " https://example.com/v1 \n", savedEndpoint: "https://example.com/v1"))
    }
    func testKeepCannotTransferBetweenEndpointsOrUseEmptyEndpoint() {
        for endpoint in ["https://other.example/v1", ""] {
            XCTAssertThrowsError(try RemoteCredentialIntent.keepExisting.valueToWrite(endpoint: endpoint, savedEndpoint: "https://example.com/v1"))
        }
        XCTAssertThrowsError(try RemoteCredentialIntent.keepExisting.valueToWrite(endpoint: "", savedEndpoint: ""))
    }
    func testReplacePreservesExactNonemptySecretAndRejectsInvalidDraft() throws {
        XCTAssertEqual(try RemoteCredentialIntent.replace("fixture-key").valueToWrite(endpoint: "new", savedEndpoint: "old"), "fixture-key")
        for value in ["", " \n", "a\nb", String(repeating: "a", count: 8193)] {
            XCTAssertThrowsError(try RemoteCredentialIntent.replace(value).valueToWrite(endpoint: "new", savedEndpoint: "old"))
        }
    }
    func testExplicitRemovalWritesEmptyOnlyToSelectedTarget() throws {
        XCTAssertEqual(try RemoteCredentialIntent.remove.valueToWrite(endpoint: "old", savedEndpoint: "old"), "")
        XCTAssertNil(try RemoteCredentialIntent.none.valueToWrite(endpoint: "new", savedEndpoint: "old", hasExistingCredential: false))
        XCTAssertThrowsError(try RemoteCredentialIntent.none.valueToWrite(endpoint: "new", savedEndpoint: "old", hasExistingCredential: true))
    }
    func testClearedDraftForSameEndpointKeepsExistingRatherThanDeletes() throws {
        let intent = RemoteCredentialIntent.draft(endpoint: " old ", savedEndpoint: "old", typedKey: "", remove: false)
        XCTAssertNil(try intent.valueToWrite(endpoint: " old ", savedEndpoint: "old"))
    }
    func testNewEndpointEmptyDraftDoesNotReuseHistoricalSecret() throws {
        let intent = RemoteCredentialIntent.draft(endpoint: "new", savedEndpoint: "old", typedKey: "", remove: false)
        XCTAssertNil(try intent.valueToWrite(endpoint: "new", savedEndpoint: "old", hasExistingCredential: false))
        XCTAssertThrowsError(try intent.valueToWrite(endpoint: "new", savedEndpoint: "old", hasExistingCredential: true))
    }
    func testExplicitRemoveWinsAndTypedReplacementIsExplicit() throws {
        XCTAssertEqual(try RemoteCredentialIntent.draft(endpoint: "old", savedEndpoint: "old", typedKey: "fixture", remove: true).valueToWrite(endpoint: "old", savedEndpoint: "old"), "")
        XCTAssertEqual(try RemoteCredentialIntent.draft(endpoint: "old", savedEndpoint: "old", typedKey: "fixture", remove: false).valueToWrite(endpoint: "old", savedEndpoint: "old"), "fixture")
    }
    func testCanonicalUnicodeEqualityDoesNotCrossKeychainByteAccounts() {
        let composed = "https://example.com/caf\u{00E9}/v1"
        let decomposed = "https://example.com/cafe\u{0301}/v1"
        XCTAssertEqual(composed, decomposed)
        XCTAssertFalse(RemoteCredentialIntent.sameEndpoint(composed, decomposed))
        XCTAssertThrowsError(try RemoteCredentialIntent.keepExisting.valueToWrite(endpoint: decomposed, savedEndpoint: composed))
        XCTAssertEqual(RemoteCredentialIntent.draft(endpoint: decomposed, savedEndpoint: composed, typedKey: "", remove: false), .none)
    }

}
