import XCTest
@testable import JarvisEVO

final class WebSourcePolicyTests: XCTestCase {
    // A normalization-first parser can turn unusual authority spellings into internal addresses.
    func testRejectsUnsafeAndAmbiguousURLs() {
        let inputs = ["http://1.1.1.1/", "file:///etc/passwd", "https://127.0.0.1/", "https://10.1.2.3/",
                      "https://192.168.1.1/", "https://169.254.169.254/", "https://100.64.0.1/",
                      "https://172.16.0.1/", "https://198.18.0.1/", "https://192.0.2.1/",
                      "https://224.0.0.1/", "https://0.0.0.0/", "https://2130706433/",
                      "https://0177.0.0.1/", "https://0x7f.0.0.1/", "https://1.1.1.1:444/",
                      "https://user:pass@1.1.1.1/", "https://1.1.1.1/?token=x", "https://1.1.1.1/#x",
                      "https://[::1]/", "https://[::ffff:1.1.1.1]/", "https://1.1.1.1\\@127.0.0.1/",
                      "https://1.1.1.1/\n", "https://%31.1.1.1/", "https://1.1.1.1./"]
        for input in inputs { XCTAssertThrowsError(try UserSuppliedWebURL(input), input) }
    }

    func testPublicHostnamePreservedButLocalAndNumericAlternativesRejected() throws {
        XCTAssertEqual(try UserSuppliedWebURL("https://example.com/article").hostname, "example.com")
        for url in ["https://localhost/", "https://printer.local/", "https://service.internal/", "https://0x7f.0.0.1/"] {
            XCTAssertThrowsError(try UserSuppliedWebURL(url))
        }
    }

    func testCanonicalPublicURLPreservesExplicitPath() throws {
        let url = try UserSuppliedWebURL("https://1.1.1.1/help")
        XCTAssertEqual(url.url.absoluteString, "https://1.1.1.1/help")
        XCTAssertEqual(try UserSuppliedWebURL("https://8.8.8.8:443/").url.host, "8.8.8.8")
    }

    func testResponsePolicyRejectsCompressionStatusTypeAndSize() throws {
        func validate(_ status: Int = 200, _ headers: [(String, String)] = [("Content-Type", "text/plain")]) throws -> String {
            try WebResponsePolicy.validate(status: status, fields: headers)
        }
        XCTAssertEqual(try validate(), "text/plain")
        for status in [100, 101, 206, 301, 401, 403, 407, 429, 500] { XCTAssertThrowsError(try validate(status)) }
        let cases: [[(String, String)]] = [
            [("Content-Type", "text/html"), ("Content-Encoding", "gzip")],
            [("Content-Type", "text/html"), ("Content-Encoding", "br")],
            [("Content-Type", "image/png")], [("Content-Type", "text/plain; charset=iso-8859-1")],
            [("Content-Type", "text/plain"), ("Content-Length", "262145")],
            [("Content-Type", "text/plain"), ("Content-Length", "-1")],
            [("Content-Type", "text/plain"), ("Content-Type", "text/html")],
            [("Content-Type", "text/plain"), ("Content-Length", "1"), ("Transfer-Encoding", "chunked")]
        ]
        for headers in cases { XCTAssertThrowsError(try validate(200, headers)) }
        XCTAssertEqual(try validate(200, [("Content-Type", "text/html; charset=UTF-8"), ("Transfer-Encoding", "chunked")]), "text/html")
    }

    func testBodyAccumulatorDoesNotAppendOversizedChunk() throws {
        var body = BoundedWebBody()
        try body.append(Data(repeating: 65, count: 262144))
        XCTAssertThrowsError(try body.append(Data([66])))
        XCTAssertEqual(body.data.count, 262144)
        XCTAssertEqual(body.data.last, 65)
    }
}
