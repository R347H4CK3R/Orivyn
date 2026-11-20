import XCTest
@testable import JarvisEVO

@MainActor
final class FreeOnlineChatStateTests: XCTestCase {
    private let choice = OpenRouterFreeModel(id: "example/chat:free", name: "Example")

    func testAutoIsDefaultButNeedsExplicitConsentAndReportsActualModel() async {
        var calls = 0
        var textSeen = ""
        let state = FreeOnlineChatState(fetchCatalog: { [self.choice] }, complete: { _, _, _ in
            XCTFail("Auto must not use manual transport"); return ""
        }, completeAutomatically: { text, _ in
            calls += 1; textSeen = text
            return FreeOnlineCompletion(model: self.choice, text: "Auto answer")
        })
        XCTAssertTrue(state.usesAutomaticSelection)
        XCTAssertFalse(state.hasConsented)
        state.apiKey = "synthetic-test-only"
        state.draft = "New coding question"
        await state.refreshCatalog()
        await state.send()
        XCTAssertEqual(calls, 0)
        state.useFreeOnlineAuto()
        await state.send()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(textSeen, "New coding question")
        XCTAssertEqual(state.lastResponseModelName, choice.name)
        XCTAssertEqual(state.response, "Auto answer")
        state.returnToOffline()
        XCTAssertFalse(state.hasConsented)
        XCTAssertEqual(state.apiKey, "")
    }

    func testAutoCancellationAndRateLimitKeepNewDraftWithoutFallback() async {
        var continuation: CheckedContinuation<FreeOnlineCompletion, Error>?
        var calls = 0
        let state = FreeOnlineChatState(fetchCatalog: { [self.choice] }, complete: { _, _, _ in
            XCTFail("No manual fallback"); return ""
        }, completeAutomatically: { _, _ in
            calls += 1
            if calls == 2 { throw OpenRouterFreeError.rateLimited }
            return try await withCheckedThrowingContinuation { continuation = $0 }
        })
        state.useFreeOnlineAuto()
        state.apiKey = "synthetic-test-only"
        state.draft = "New text"
        let first = Task { await state.send() }
        for _ in 0..<100 { if continuation != nil { break }; await Task.yield() }
        XCTAssertNotNil(continuation)
        await state.send()
        XCTAssertEqual(calls, 1)
        state.cancel()
        continuation?.resume(returning: .init(model: choice, text: "Late"))
        await first.value
        XCTAssertNil(state.response)
        XCTAssertNil(state.lastResponseModelName)
        XCTAssertEqual(state.draft, "New text")
        await state.send()
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(state.draft, "New text")
        XCTAssertTrue(state.errorMessage?.contains("offline") ?? false)
    }

    func testManualPreferenceIsNotResetToAutoByRefreshOrClosing() async {
        let state = FreeOnlineChatState(fetchCatalog: { [self.choice] }, complete: { _, _, _ in "Manual" })
        await state.refreshCatalog()
        state.useFreeOnline(modelID: choice.id)
        XCTAssertFalse(state.usesAutomaticSelection)
        state.returnToOffline()
        XCTAssertFalse(state.hasConsented)
        XCTAssertFalse(state.usesAutomaticSelection)
        XCTAssertEqual(state.selectedModelID, choice.id)
        await state.refreshCatalog()
        XCTAssertFalse(state.usesAutomaticSelection)
        XCTAssertFalse(state.hasConsented)
        state.useFreeOnlineAuto()
        XCTAssertTrue(state.usesAutomaticSelection)
    }

    func testDefaultAndMissingConsentOrKeyNeverCallTransport() async {
        var calls = 0
        let state = FreeOnlineChatState(fetchCatalog: { [self.choice] }, complete: { _, _, _ in calls += 1; return "answer" })
        XCTAssertFalse(state.hasConsented)
        state.draft = "Fresh text"
        state.apiKey = "synthetic-test-only"
        await state.send()
        XCTAssertEqual(calls, 0)
        await state.refreshCatalog()
        state.useFreeOnline(modelID: choice.id)
        state.apiKey = ""
        await state.send()
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(state.draft, "Fresh text")
    }

    func testOnlyIndependentNewDraftIsSentAndSuccessfulTurnClearsIt() async {
        var seen: [String] = []
        let state = FreeOnlineChatState(fetchCatalog: { [self.choice] }, complete: { model, text, key in
            seen = [model, text, key]; return "Answer"
        })
        await state.refreshCatalog()
        state.useFreeOnline(modelID: choice.id)
        state.apiKey = "synthetic-test-only"
        state.draft = "New turn only"
        await state.send()
        XCTAssertEqual(seen, [choice.id, "New turn only", "synthetic-test-only"])
        XCTAssertEqual(state.response, "Answer")
        XCTAssertEqual(state.draft, "")
        XCTAssertFalse(state.isSending)
    }

    func testFailurePreservesDraftAndDoesNotExposeUnderlyingError() async {
        let state = FreeOnlineChatState(fetchCatalog: { [self.choice] }, complete: { _, _, _ in
            throw NSError(domain: "secret-sensitive-url", code: 1)
        })
        await state.refreshCatalog()
        state.useFreeOnline(modelID: choice.id)
        state.apiKey = "synthetic-test-only"
        state.draft = "Keep for retry"
        await state.send()
        XCTAssertEqual(state.draft, "Keep for retry")
        XCTAssertNil(state.response)
        XCTAssertFalse(state.errorMessage?.contains("secret") ?? true)
    }

    func testDoubleSendAndLateCompletionAfterCancellationAreIgnored() async {
        var continuation: CheckedContinuation<String, Error>?
        var calls = 0
        let state = FreeOnlineChatState(fetchCatalog: { [self.choice] }, complete: { _, _, _ in
            calls += 1
            return try await withCheckedThrowingContinuation { continuation = $0 }
        })
        await state.refreshCatalog()
        state.useFreeOnline(modelID: choice.id)
        state.apiKey = "synthetic-test-only"
        state.draft = "Preserve me"
        let first = Task { await state.send() }
        for _ in 0..<100 { if continuation != nil { break }; await Task.yield() }
        XCTAssertNotNil(continuation)
        await state.send()
        XCTAssertEqual(calls, 1)
        state.returnToOffline()
        XCTAssertEqual(state.apiKey, "")
        XCTAssertFalse(state.hasConsented)
        continuation?.resume(returning: "Stale answer")
        await first.value
        XCTAssertNil(state.response)
        XCTAssertEqual(state.draft, "Preserve me")
        XCTAssertFalse(state.isSending)
    }

    func testModelMustBeInCatalogAndRefreshFailureRevokesConsent() async {
        var fail = false
        let state = FreeOnlineChatState(fetchCatalog: {
            if fail { throw URLError(.notConnectedToInternet) }; return [self.choice]
        }, complete: { _, _, _ in XCTFail("Must not send"); return "" })
        state.useFreeOnline(modelID: choice.id)
        XCTAssertFalse(state.hasConsented)
        await state.refreshCatalog()
        state.useFreeOnline(modelID: choice.id)
        XCTAssertTrue(state.hasConsented)
        fail = true
        await state.refreshCatalog()
        XCTAssertFalse(state.hasConsented)
        XCTAssertTrue(state.models.isEmpty)
    }
    func testChangingModelOrEditingDraftInvalidatesInFlightAnswer() async {
        for changeModel in [false, true] {
            var continuation: CheckedContinuation<String, Error>?
            let other = OpenRouterFreeModel(id: "example/other:free", name: "Other")
            var receivedModel = ""
            let state = FreeOnlineChatState(fetchCatalog: { [self.choice, other] }, complete: { model, _, _ in
                receivedModel = model
                return try await withCheckedThrowingContinuation { continuation = $0 }
            })
            await state.refreshCatalog()
            state.useFreeOnline(modelID: choice.id)
            state.apiKey = "synthetic-test-only"
            state.draft = "Original new text"
            let first = Task { await state.send() }
            for _ in 0..<100 { if continuation != nil { break }; await Task.yield() }
            XCTAssertNotNil(continuation)
            if changeModel { state.useFreeOnline(modelID: other.id) }
            else { state.draft = "Changed text" }
            continuation?.resume(returning: "Obsolete answer")
            await first.value
            XCTAssertEqual(receivedModel, choice.id)
            XCTAssertNil(state.response)
            XCTAssertEqual(state.draft, changeModel ? "Original new text" : "Changed text")
            XCTAssertFalse(state.isSending)
        }
    }

    func testLateCatalogCannotUndoReturnToOffline() async {
        var continuation: CheckedContinuation<[OpenRouterFreeModel], Error>?
        let state = FreeOnlineChatState(fetchCatalog: {
            try await withCheckedThrowingContinuation { continuation = $0 }
        }, complete: { _, _, _ in XCTFail("Unexpected send"); return "" })
        let loading = Task { await state.refreshCatalog() }
        for _ in 0..<100 { if continuation != nil { break }; await Task.yield() }
        XCTAssertNotNil(continuation)
        state.returnToOffline()
        continuation?.resume(returning: [choice])
        await loading.value
        XCTAssertTrue(state.models.isEmpty)
        XCTAssertFalse(state.hasConsented)
        XCTAssertFalse(state.isLoadingCatalog)
    }

}
