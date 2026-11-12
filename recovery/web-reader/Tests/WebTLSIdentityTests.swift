import XCTest
import Security
@testable import JarvisEVO

final class WebTLSIdentityTests: XCTestCase {
    // Test-only root certificate. The production path never adds anchors or accepts this certificate.
    func testPlatformTrustAcceptsOnlyCorrectHostnameAndValidity() throws {
        let correct = try trust(anchorFixture: true)
        XCTAssertTrue(WebTLSIdentity.evaluate(correct, hostname: "public.example.com"))
        let wrong = try trust(anchorFixture: true)
        XCTAssertFalse(WebTLSIdentity.evaluate(wrong, hostname: "other.example.com"))
        let expired = try trust(anchorFixture: true)
        XCTAssertEqual(SecTrustSetVerifyDate(expired, Date(timeIntervalSince1970: 4_102_444_800) as CFDate), errSecSuccess)
        XCTAssertFalse(WebTLSIdentity.evaluate(expired, hostname: "public.example.com"))
    }

    func testUntrustedCertificateCannotBeAcceptedByHostnameOverride() throws {
        XCTAssertFalse(WebTLSIdentity.evaluate(try trust(anchorFixture: false), hostname: "public.example.com"))
    }

    private func trust(anchorFixture: Bool) throws -> SecTrust {
        #if SWIFT_PACKAGE
        let url = try XCTUnwrap(Bundle.module.url(forResource: "WebTLSIdentity", withExtension: "der"))
        #else
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "WebTLSIdentity", withExtension: "der"))
        #endif
        let bytes = try Data(contentsOf: url)
        let certificate = try XCTUnwrap(SecCertificateCreateWithData(nil, bytes as CFData))
        var result: SecTrust?
        XCTAssertEqual(SecTrustCreateWithCertificates(certificate, SecPolicyCreateSSL(true, "public.example.com" as CFString), &result), errSecSuccess)
        let trust = try XCTUnwrap(result)
        if anchorFixture {
            XCTAssertEqual(SecTrustSetAnchorCertificates(trust, [certificate] as CFArray), errSecSuccess)
            XCTAssertEqual(SecTrustSetAnchorCertificatesOnly(trust, true), errSecSuccess)
        }
        XCTAssertEqual(SecTrustSetVerifyDate(trust, Date(timeIntervalSince1970: 1_798_761_600) as CFDate), errSecSuccess)
        return trust
    }
}
