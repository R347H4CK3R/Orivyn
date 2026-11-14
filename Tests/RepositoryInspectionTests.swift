import XCTest
import CryptoKit
@testable import JarvisEVO

@MainActor
final class RepositoryInspectionTests: XCTestCase {
    private let commit = String(repeating: "a", count: 40)
    private let tree = String(repeating: "b", count: 40)
    private let token = "test-token-not-a-real-credential"
    private func json(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
    private func blobSHA(_ data: Data) -> String {
        var bytes = Data("blob \(data.count)\0".utf8); bytes.append(data)
        return Insecure.SHA1.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    private func fixture(text: String = "let answer = 42\n", truncated: Bool = false, privateRepo: Bool = true, wrongBlob: Bool = false) throws -> [InspectionReply] {
        let bytes = Data(text.utf8), sha = blobSHA(bytes)
        return [
            InspectionReply(body: try json(["full_name":"R347H4CK3R/Orivyn","private":privateRepo,"default_branch":"feature/main"])),
            InspectionReply(body: try json(["sha":commit,"commit":["tree":["sha":tree]]])),
            InspectionReply(body: try json(["sha":tree,"truncated":truncated,"tree":[["path":"Core/Main.swift","type":"blob","mode":"100644","sha":sha,"size":bytes.count],["path":"link","type":"blob","mode":"120000","sha":sha,"size":bytes.count]]])),
            InspectionReply(body: try json(["sha":sha,"encoding":"base64","size":bytes.count,"content":(wrongBlob ? Data(repeating: 120, count: bytes.count) : bytes).base64EncodedString()]))
        ]
    }
    func testPinsPrivateCommitAndVerifiesSelectedTextBlob() async throws {
        let transport = InspectionTransport(replies: try fixture())
        let client = try RepositoryInspectionClient(token: token, transport: transport)
        let snapshot = try await client.loadSnapshot()
        XCTAssertEqual(snapshot.commitSHA, commit)
        XCTAssertEqual(snapshot.files.map(\.path), ["Core/Main.swift"])
        let file = try await client.readFile(path: "Core/Main.swift", snapshotID: snapshot.id)
        XCTAssertEqual(file.text, "let answer = 42\n")
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 4)
        XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "GET" && $0.url?.host == "api.github.com" && $0.value(forHTTPHeaderField: "Authorization") == "Bearer " + token })
        XCTAssertTrue(requests[1].url!.absoluteString.contains("feature%2Fmain"))
        XCTAssertTrue(requests[2].url!.absoluteString.contains("/git/trees/" + tree))
        XCTAssertTrue(requests[3].url!.absoluteString.contains("/git/blobs/" + file.blobSHA))
    }
    func testRejectsPublicRepositoryBeforeFetchingSource() async throws {
        let transport = InspectionTransport(replies: try fixture(privateRepo: false))
        let client = try RepositoryInspectionClient(token: token, transport: transport)
        do { _ = try await client.loadSnapshot(); XCTFail("Public repo accepted") } catch { XCTAssertEqual(error as? RepositoryInspectionError, .repositoryMismatch) }
        let count = await transport.requests.count; XCTAssertEqual(count, 1)
    }
    func testRejectsTruncatedTree() async throws {
        let client = try RepositoryInspectionClient(token: token, transport: InspectionTransport(replies: try fixture(truncated: true)))
        do { _ = try await client.loadSnapshot(); XCTFail("Partial tree accepted") } catch { XCTAssertEqual(error as? RepositoryInspectionError, .bounds) }
    }
    func testRejectsCorruptedBlobAndUnlistedPath() async throws {
        let transport = InspectionTransport(replies: try fixture(wrongBlob: true))
        let client = try RepositoryInspectionClient(token: token, transport: transport)
        let snapshot = try await client.loadSnapshot()
        do { _ = try await client.readFile(path: "../secret", snapshotID: snapshot.id); XCTFail("Unlisted path accepted") } catch { XCTAssertEqual(error as? RepositoryInspectionError, .selection) }
        do { _ = try await client.readFile(path: "Core/Main.swift", snapshotID: snapshot.id); XCTFail("Corrupt blob accepted") } catch { XCTAssertEqual(error as? RepositoryInspectionError, .integrity) }
    }
    func testClearingCredentialsInvalidatesSelectionAndPreventsMoreRequests() async throws {
        let transport = InspectionTransport(replies: try fixture())
        let client = try RepositoryInspectionClient(token: token, transport: transport)
        let snapshot = try await client.loadSnapshot()
        await client.clearCredentials()
        do { _ = try await client.readFile(path: "Core/Main.swift", snapshotID: snapshot.id); XCTFail("Cleared token used") } catch { XCTAssertEqual(error as? RepositoryInspectionError, .credentials) }
        let count = await transport.requests.count; XCTAssertEqual(count, 3)
    }
    func testRejectsResponseFromDifferentOriginWithoutExposingBody() async throws {
        let transport = InspectionTransport(replies: [InspectionReply(body: Data("private server details".utf8), url: URL(string:"https://evil.example/"))])
        let client = try RepositoryInspectionClient(token: token, transport: transport)
        do { _ = try await client.loadSnapshot(); XCTFail("Different origin accepted") } catch {
            XCTAssertEqual(error as? RepositoryInspectionError, .response)
            XCTAssertFalse(error.localizedDescription.contains("private server details"))
        }
    }
    func testRejectsBinaryEvenWhenBlobHashMatches() async throws {
        let client = try RepositoryInspectionClient(token: token, transport: InspectionTransport(replies: try fixture(text: "a\0b")))
        let snapshot = try await client.loadSnapshot()
        do { _ = try await client.readFile(path: "Core/Main.swift", snapshotID: snapshot.id); XCTFail("Binary accepted") } catch { XCTAssertEqual(error as? RepositoryInspectionError, .notText) }
    }
    func testOversizedResponseIsRejectedEvenIfTransportIgnoresLimit() async throws {
        let transport = InspectionTransport(replies: [InspectionReply(body: Data(repeating: 32, count: 65_537))])
        let client = try RepositoryInspectionClient(token: token, transport: transport)
        do { _ = try await client.loadSnapshot(); XCTFail("Oversized metadata accepted") } catch { XCTAssertEqual(error as? RepositoryInspectionError, .bounds) }
    }
    func testRepinningRejectsAnOlderSnapshotSelection() async throws {
        let first = try fixture()
        let transport = InspectionTransport(replies: Array(first.prefix(3)) + Array(first.prefix(3)))
        let client = try RepositoryInspectionClient(token: token, transport: transport)
        let old = try await client.loadSnapshot()
        let newer = try await client.loadSnapshot()
        XCTAssertNotEqual(old.id, newer.id)
        do { _ = try await client.readFile(path: "Core/Main.swift", snapshotID: old.id); XCTFail("Stale snapshot used") } catch { XCTAssertEqual(error as? RepositoryInspectionError, .selection) }
        let count = await transport.requests.count; XCTAssertEqual(count, 6)
    }
    func testClearCancelsInFlightRequestAndRejectsLateResponse() async throws {
        let transport = DelayedInspectionTransport(body: try fixture()[0].body)
        let client = try RepositoryInspectionClient(token: token, transport: transport)
        let loading = Task { try await client.loadSnapshot() }
        let deadline = ContinuousClock.now + .seconds(3)
        while !(await transport.started) {
            guard ContinuousClock.now < deadline else { loading.cancel(); XCTFail("Request did not start"); return }
            try await Task.sleep(for: .milliseconds(5))
        }
        await client.clearCredentials()
        await transport.complete()
        do { _ = try await loading.value; XCTFail("Late cleared response accepted") } catch { XCTAssertEqual(error as? RepositoryInspectionError, .credentials) }
        let cancelled = await transport.observedCancellation
        let count = await transport.count
        XCTAssertTrue(cancelled)
        XCTAssertEqual(count, 1, "Cleared metadata must not trigger commit/tree reads")
    }
    func testRejectsTraversalLikeDefaultBranchWithoutSecondRequest() async throws {
        let body = try json(["full_name":"R347H4CK3R/Orivyn","private":true,"default_branch":".."])
        let transport = InspectionTransport(replies: [InspectionReply(body: body)])
        let client = try RepositoryInspectionClient(token: token, transport: transport)
        do { _ = try await client.loadSnapshot(); XCTFail("Invalid branch accepted") } catch { XCTAssertEqual(error as? RepositoryInspectionError, .response) }
        let count = await transport.requests.count; XCTAssertEqual(count, 1)
    }
    func testExplicitRefUsesEncodedPathAndPinsReturnedCommit() async throws {
        let transport = InspectionTransport(replies: try fixture())
        let client = try RepositoryInspectionClient(token: token, transport: transport)
        let snapshot = try await client.loadSnapshot(reference: "integration/native-fix")
        XCTAssertEqual(snapshot.branch, "integration/native-fix")
        XCTAssertEqual(snapshot.commitSHA, commit)
        let requests = await transport.requests
        XCTAssertEqual(requests[1].url?.absoluteString, "https://api.github.com/repos/R347H4CK3R/Orivyn/commits/integration%2Fnative-fix")
    }
    func testExplicitCommitMustMatchBeforeReadingTree() async throws {
        let transport = InspectionTransport(replies: try fixture())
        let client = try RepositoryInspectionClient(token: token, transport: transport)
        do { _ = try await client.loadSnapshot(reference: String(repeating: "c", count: 40)); XCTFail("Different commit accepted") }
        catch { XCTAssertEqual(error as? RepositoryInspectionError, .integrity) }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
    }
    func testExplicitCommitAcceptedWhenMatched() async throws {
        let transport = InspectionTransport(replies: try fixture())
        let client = try RepositoryInspectionClient(token: token, transport: transport)
        let snapshot = try await client.loadSnapshot(reference: commit)
        XCTAssertEqual(snapshot.branch, commit)
        XCTAssertEqual(snapshot.commitSHA, commit)
    }
    func testInvalidExplicitRefMakesNoRequest() async throws {
        for reference in ["../main", "https://other.example", "a?token=secret", "a%2Fb", "a#frag", "a b", "a//b", ".hidden", "a.lock", String(repeating: "x", count: 513)] {
            let transport = InspectionTransport(replies: [])
            let client = try RepositoryInspectionClient(token: token, transport: transport)
            do { _ = try await client.loadSnapshot(reference: reference); XCTFail("Invalid ref accepted") }
            catch { XCTAssertEqual(error as? RepositoryInspectionError, .reference) }
            let requests = await transport.requests
            XCTAssertTrue(requests.isEmpty)
        }
    }
    func testRejectsHeaderInjectionToken() {
        XCTAssertThrowsError(try RepositoryInspectionClient(token: "bad\r\nHeader: value"))
    }
}
private struct InspectionReply: Sendable {
    let body: Data
    var status = 200
    var url: URL? = nil
}
private actor InspectionTransport: MCPHTTPTransport {
    var replies: [InspectionReply]
    private(set) var requests: [URLRequest] = []
    init(replies: [InspectionReply]) { self.replies = replies }
    func send(_ request: URLRequest, maximumResponseBytes: Int, timeout: TimeInterval) async throws -> MCPHTTPResponse {
        requests.append(request)
        guard !replies.isEmpty else { throw URLError(.badServerResponse) }
        let reply = replies.removeFirst()
        return MCPHTTPResponse(url: reply.url ?? request.url!, statusCode: reply.status, headers: [:], body: reply.body)
    }
}

/// Deliberately returns a late response despite cancellation to exercise client epochs.
private actor DelayedInspectionTransport: MCPHTTPTransport {
    let body: Data
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var started = false
    private(set) var observedCancellation = false
    private(set) var count = 0
    init(body: Data) { self.body = body }
    func send(_ request: URLRequest, maximumResponseBytes: Int, timeout: TimeInterval) async throws -> MCPHTTPResponse {
        count += 1
        await withCheckedContinuation { continuation = $0; started = true }
        observedCancellation = Task.isCancelled
        return MCPHTTPResponse(url: request.url!, statusCode: 200, headers: [:], body: body)
    }
    func complete() { continuation?.resume(); continuation = nil }
}

