import XCTest
import Foundation
@testable import JarvisEVO

final class WebDNSLifecycleTests: XCTestCase {
    func testStalledSetupDeadlineCompletesCallerAndBoundsAbandonedWork() async throws {
        let api = DNSAPIFixture(blockSetup: true)
        let deadlines = ManualDNSDeadlines()
        let admission = WebDNSAdmissionPool(limit: 1)
        let resolver = PublicWebDNSResolver(api: api, deadlines: deadlines, admission: admission)
        let completed = expectation(description: "caller completes while setup is blocked")
        let result = DNSResultBox()
        let task = Task {
            do { result.store(.success(try await resolver.resolve(UserSuppliedWebURL("https://example.com/")))) }
            catch { result.store(.failure(error)) }
            completed.fulfill()
        }
        defer { api.unblock(); task.cancel() }
        await fulfillment(of: [api.started], timeout: 1)
        deadlines.fire()
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertEqual(result.error as? WebSourceError, .timeout)
        XCTAssertEqual(api.cancelCount, 0, "Cannot deallocate while the setup call is still using the reference")
        let second = DNSAPIFixture(blockSetup: false)
        let secondResolver = PublicWebDNSResolver(api: second, deadlines: ManualDNSDeadlines(), admission: admission)
        do { _ = try await secondResolver.resolve(UserSuppliedWebURL("https://example.org/")); XCTFail() }
        catch { XCTAssertEqual(error as? WebSourceError, .busy) }
        XCTAssertEqual(second.startCount, 0, "Abandoned setup retains its admission slot until cleanup")
        api.unblock()
        await fulfillment(of: [api.cleaned], timeout: 1)
        XCTAssertEqual(api.cancelCount, 1)
        XCTAssertEqual(result.completionCount, 1)
    }

    func testCancellationDoesNotWaitForBlockedSetupAndLateSuccessIsCleaned() async throws {
        let api = DNSAPIFixture(blockSetup: true)
        let deadlines = ManualDNSDeadlines()
        let resolver = PublicWebDNSResolver(api: api, deadlines: deadlines, admission: WebDNSAdmissionPool(limit: 1))
        let completed = expectation(description: "cancelled caller finishes")
        let result = DNSResultBox()
        let task = Task {
            do { result.store(.success(try await resolver.resolve(UserSuppliedWebURL("https://example.com/")))) }
            catch { result.store(.failure(error)) }
            completed.fulfill()
        }
        defer { api.unblock(); task.cancel() }
        await fulfillment(of: [api.started], timeout: 1)
        task.cancel()
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertTrue(result.error is CancellationError)
        XCTAssertEqual(api.cancelCount, 0)
        deadlines.fire() // A late deadline must not complete the continuation again.
        api.unblock()
        await fulfillment(of: [api.cleaned], timeout: 1)
        api.emit(.address("1.1.1.1", moreComing: false))
        await fulfillment(of: [api.emitted], timeout: 1)
        XCTAssertEqual(api.cancelCount, 1)
        XCTAssertEqual(result.completionCount, 1)
        XCTAssertTrue(result.error is CancellationError)
    }

    func testCallbackSuccessThenLateDeadlineCleansExactlyOnceAndReleasesSlot() async throws {
        let api = DNSAPIFixture(blockSetup: false)
        let deadlines = ManualDNSDeadlines()
        let admission = WebDNSAdmissionPool(limit: 1)
        let resolver = PublicWebDNSResolver(api: api, deadlines: deadlines, admission: admission)
        let task = Task { try await resolver.resolve(UserSuppliedWebURL("https://example.com/")) }
        await fulfillment(of: [api.started], timeout: 1)
        api.emit(.address("1.1.1.1", moreComing: false))
        let result = try await task.value
        XCTAssertEqual(result.literal, "1.1.1.1")
        await fulfillment(of: [api.cleaned], timeout: 1)
        await api.drain()
        deadlines.fire()
        task.cancel()
        XCTAssertEqual(api.cancelCount, 1)
        let next = DNSAPIFixture(blockSetup: false)
        let nextResolver = PublicWebDNSResolver(api: next, deadlines: ManualDNSDeadlines(), admission: admission)
        let nextTask = Task { try await nextResolver.resolve(UserSuppliedWebURL("https://example.org/")) }
        await fulfillment(of: [next.started], timeout: 1)
        next.emit(.address("8.8.8.8", moreComing: false))
        let nextResult = try await nextTask.value
        XCTAssertEqual(nextResult.literal, "8.8.8.8")
        await fulfillment(of: [next.cleaned], timeout: 1)
    }

    func testPrivateAnswerAndTooManyRecordsFailBeforeConnection() async throws {
        for excess in [false, true] {
            let api = DNSAPIFixture(blockSetup: false)
            let resolver = PublicWebDNSResolver(api: api, deadlines: ManualDNSDeadlines(), admission: WebDNSAdmissionPool(limit: 1))
            let task = Task { try await resolver.resolve(UserSuppliedWebURL("https://example.com/")) }
            await fulfillment(of: [api.started], timeout: 1)
            if excess {
                for _ in 0..<17 { api.emit(.address("1.1.1.1", moreComing: true), signal: false) }
            } else { api.emit(.address("127.0.0.1", moreComing: false), signal: false) }
            do { _ = try await task.value; XCTFail() }
            catch { XCTAssertEqual(error as? WebSourceError, excess ? .invalidResponse : .unsafeAddress) }
            await fulfillment(of: [api.cleaned], timeout: 1)
            XCTAssertEqual(api.cancelCount, 1)
        }
    }
}

private final class DNSResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<PublicWebIPv4, Error>?
    private var count = 0
    func store(_ result: Result<PublicWebIPv4, Error>) { lock.withLock { self.result = result; count += 1 } }
    var error: Error? { lock.withLock { if case .failure(let error)? = result { return error }; return nil } }
    var completionCount: Int { lock.withLock { count } }
}

private final class ManualDNSDeadlines: WebDNSDeadlineScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var actions: [@Sendable () -> Void] = []
    func schedule(after seconds: TimeInterval, action: @escaping @Sendable () -> Void) -> any WebDNSDeadline {
        lock.withLock { actions.append(action) }
        return Token()
    }
    func fire() { for action in lock.withLock({ actions }) { action() } }
    private final class Token: WebDNSDeadline, @unchecked Sendable { func cancel() {} }
}

private final class DNSAPIFixture: WebDNSStarting, @unchecked Sendable {
    let started = XCTestExpectation(description: "DNS setup entered")
    let cleaned = XCTestExpectation(description: "DNS reference cleaned")
    let emitted = XCTestExpectation(description: "DNS callback emitted")
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private let blockSetup: Bool
    private var callback: (@Sendable (WebDNSRecord) -> Void)?
    private var queue: DispatchQueue?
    private var starts = 0
    private var cancels = 0
    init(blockSetup: Bool) { self.blockSetup = blockSetup }
    var startCount: Int { lock.withLock { starts } }
    var cancelCount: Int { lock.withLock { cancels } }
    func start(host: String, queue: DispatchQueue, receive: @escaping @Sendable (WebDNSRecord) -> Void) throws -> any WebDNSService {
        dispatchPrecondition(condition: .onQueue(queue))
        lock.withLock { starts += 1; self.queue = queue; callback = receive }
        started.fulfill()
        if blockSetup { gate.wait() }
        return Service(queue: queue) { [self] in lock.withLock { cancels += 1 }; cleaned.fulfill() }
    }
    func unblock() { gate.signal() }
    func drain() async {
        guard let queue = lock.withLock({ queue }) else { return }
        await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
    }
    func emit(_ record: WebDNSRecord, signal: Bool = true) {
        let target = lock.withLock { (queue, callback) }
        target.0?.async { [self] in target.1?(record); if signal { emitted.fulfill() } }
    }
    private final class Service: WebDNSService, @unchecked Sendable {
        let queue: DispatchQueue
        let cleanup: @Sendable () -> Void
        init(queue: DispatchQueue, cleanup: @escaping @Sendable () -> Void) { self.queue = queue; self.cleanup = cleanup }
        func cancel() { dispatchPrecondition(condition: .onQueue(queue)); cleanup() }
    }
}
