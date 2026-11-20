import XCTest
@testable import JarvisEVO
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class OpenRouterFreeProviderTests: XCTestCase {
    func testAutoClassifiesLocallyAndSelectsStableVerifiedTaskFit() throws {
        let rows = try models([row("particle-ai/particle-1:free"), row("inclusionai/ling-3.2-flash:free"), row("dots-studio/dots-3-note-preview:free")])
        let cases: [(String, OpenRouterFreeModel.SuggestedUse, String)] = [
            ("Fix this Swift code", .coding, "particle-ai/particle-1:free"),
            ("Prove this theorem step by step", .hardProblems, "inclusionai/ling-3.2-flash:free"),
            ("Rewrite my email", .writing, "dots-studio/dots-3-note-preview:free"),
            ("Hello there", .everyday, "dots-studio/dots-3-note-preview:free")]
        for (text, task, id) in cases {
            XCTAssertEqual(FreeOnlineAutoRouter.classify(text), task)
            XCTAssertEqual(try FreeOnlineAutoRouter.select(text: text, verifiedModels: rows).id, id)
            XCTAssertEqual(try FreeOnlineAutoRouter.select(text: text, verifiedModels: Array(rows.reversed())).id, id)
        }
        XCTAssertEqual(FreeOnlineAutoRouter.classify("decoding a painting"), .everyday)
        XCTAssertEqual(FreeOnlineAutoRouter.classify(String(repeating: "a", count: 4097) + " code"), .everyday)
        XCTAssertThrowsError(try FreeOnlineAutoRouter.select(text: "code", verifiedModels: []))
        XCTAssertEqual(try FreeOnlineAutoRouter.select(text: "code", verifiedModels: [rows[0]]).id, rows[0].id)
    }

    func testAutoUsesFreshCatalogNotPreviewAndPostsOnlyExactSingleTurn() async throws {
        let freshID = "particle-ai/particle-1:free"
        let answer = try JSONSerialization.data(withJSONObject: ["model": freshID, "choices": [["finish_reason": "stop", "message": ["role": "assistant", "content": "Hello"]]]])
        let mock = MockTransport(responses: [try catalog([row()]), try catalog([row(freshID)]), answer])
        let provider = OpenRouterFreeProvider(transport: mock.send)
        _ = try await provider.fetchCatalog()
        let result = try await provider.completeAutomatically(newlyAuthoredText: "Fix my code", apiKey: "test-key")
        XCTAssertEqual(result.model.id, freshID)
        XCTAssertEqual(result.text, "Hello")
        let requests = await mock.requests
        XCTAssertEqual(requests.map(\.httpMethod), ["GET", "GET", "POST"])
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[2].httpBody!) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, freshID)
        XCTAssertEqual(body["messages"] as? [[String: String]], [["role": "user", "content": "Fix my code"]])
        XCTAssertEqual(Set(body.keys), Set(["model", "messages", "stream", "max_tokens", "provider"]))
        let policy = try XCTUnwrap(body["provider"] as? [String: Any])
        XCTAssertEqual(policy["max_price"] as? [String: Int], ["prompt": 0, "completion": 0, "request": 0])
        XCTAssertEqual(policy["allow_fallbacks"] as? Bool, false)
    }

    func testAutoCancellationAfterFreshCatalogNeverPosts() async throws {
        let mock = MockTransport(responses: [try catalog([row()])])
        let provider = OpenRouterFreeProvider(transport: { request, limit in
            let result = try await mock.send(request, limit)
            withUnsafeCurrentTask { $0?.cancel() }
            return result
        })
        let task = Task { try await provider.completeAutomatically(newlyAuthoredText: "code", apiKey: "test-key") }
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        let requests = await mock.requests
        XCTAssertEqual(requests.map(\.httpMethod), ["GET"])
    }

    func testAutoEmptyOrPaidCatalogNeverPosts() async throws {
        for rows in [[], [row("particle-ai/particle-1:free", pricing: ["prompt": "1", "completion": "0"])]] {
            let mock = MockTransport(responses: [try catalog(rows)])
            do { _ = try await OpenRouterFreeProvider(transport: mock.send).completeAutomatically(newlyAuthoredText: "code", apiKey: "test-key"); XCTFail() } catch {}
            let requests = await mock.requests
            XCTAssertEqual(requests.map(\.httpMethod), ["GET"])
        }
    }

    func testReviewedProfilesIncludeCodingNamesWithoutCoderSlugs() {
        for id in ["particle-ai/particle-1:free", "recursive/flint-v1.0:free"] {
            let model = OpenRouterFreeModel(id: id, name: "Display name")
            XCTAssertEqual(model.suggestedUses.first, .coding)
            XCTAssertTrue(model.shortDescription.contains("code"))
            XCTAssertTrue(model.matchesSearch("coding"))
            XCTAssertTrue(model.matchesSearch(id))
        }
    }

    func testAllReviewedProfilesAreDistinctAndTextOnlyWithHonestUnknownFallback() throws {
        let ids = ["baidu/ernie-5.5-flash-preview:free", "dots-studio/dots-3-note-preview:free", "google/gemma-4-26b-a4b-it:free", "google/gemma-4-31b-it:free", "inclusionai/ling-3.2-flash:free", "liquid/lfm-3-1.7b:free", "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free", "nvidia/nemotron-3-ultra-550b-a55b:free", "nvidia/nemotron-3.5-lightning:free", "nvidia/nemotron-3.5-super-vl:free", "particle-ai/particle-1:free", "recursive/flint-v1.0:free"]
        let descriptions = ids.map { OpenRouterFreeModel(id: $0, name: $0).shortDescription }
        XCTAssertEqual(Set(descriptions).count, 12)
        XCTAssertTrue(descriptions.allSatisfy { $0.contains("Text only here") && $0.contains("free usage limits") })
        let unknown = OpenRouterFreeModel(id: "new-maker/future-model:free", name: "Future Choice")
        XCTAssertTrue(unknown.shortDescription.contains("not reviewed"))
        XCTAssertTrue(unknown.matchesSearch("future"))
        XCTAssertTrue(unknown.matchesSearch(""))
        XCTAssertFalse(unknown.matchesSearch("unrelated"))
        XCTAssertEqual(try models([row(unknown.id)]).map(\.id), [unknown.id])
        XCTAssertTrue(try models([row("particle-ai/particle-1:free", pricing: ["prompt": "1", "completion": "0"])]).isEmpty)
    }

    func testReasoningAndPrivacyNotesAreVisibleAndSearchable() {
        for id in ["inclusionai/ling-3.2-flash:free", "nvidia/nemotron-3-ultra-550b-a55b:free", "google/gemma-4-31b-it:free"] {
            XCTAssertTrue(OpenRouterFreeModel(id: id, name: id).suggestedUses.contains(.hardProblems))
        }
        let liquid = OpenRouterFreeModel(id: "liquid/lfm-3-1.7b:free", name: "Liquid")
        XCTAssertTrue(liquid.shortDescription.contains("may retain"))
        XCTAssertTrue(liquid.matchesSearch("structured"))
    }

    // Compact fixture captured from the public official models schema, 2026-11-20.
    private func row(_ id: String = "example/chat:free", pricing: [String: Any] = ["prompt": "0", "completion": "0"]) -> [String: Any] {
        ["id": id, "name": "Example Chat", "pricing": pricing,
         "architecture": ["input_modalities": ["text"], "output_modalities": ["text"]],
         "endpoints": ["/api/v1/chat/completions"]]
    }
    private func catalog(_ rows: [[String: Any]]) throws -> Data { try JSONSerialization.data(withJSONObject: ["data": rows]) }
    private func models(_ rows: [[String: Any]]) throws -> [OpenRouterFreeModel] {
        try OpenRouterFreeProvider.parseCatalog(catalog(rows), now: Date(timeIntervalSince1970: 1_795_132_800))
    }
    func testOnlyConcreteFreeTextRowsWithExplicitZeroPricingAreEligible() throws {
        var image = row("example/image:free"); image["architecture"] = ["input_modalities": ["text"], "output_modalities": ["image"]]
        let rows = [row(), row("example/paid"), row("openrouter/free"), row("example/x:FREE"),
                    row("example/auto:free"), row("example/x:free:online"), row("example/x:free", pricing: ["prompt":"0"]),
                    row("example/nonzero:free", pricing: ["prompt":"0", "completion":"0.000001"]), image]
        XCTAssertEqual(try models(rows).map(\.id), ["example/chat:free"])
    }
    func testDecimalZeroNeverUsesFloatingPointUnderflow() throws {
        for value: Any in ["-0", "-1", "NaN", "0e-999", "0.000000000000000000000000000000000000000000000000000001", " 0", 0, NSNull()] {
            XCTAssertTrue(try models([row(pricing: ["prompt": value, "completion":"0"])]).isEmpty)
        }
        XCTAssertEqual(try models([row(pricing: ["prompt":"0.000", "completion":"00.00"])]).count, 1)
    }
    func testOptionalChargesMustBeKnownAndZero() throws {
        for pricing: [String: Any] in [ ["prompt":"0","completion":"0","request":"0.1"],
            ["prompt":"0","completion":"0","new_charge":"0"], ["prompt":"0","completion":"0","image":NSNull()] ] {
            XCTAssertTrue(try models([row(pricing: pricing)]).isEmpty)
        }
        XCTAssertEqual(try models([row(pricing: ["prompt":"0","completion":"0","request":"0","image":"0"])]).count, 1)
    }
    func testDuplicateIDsAreExcludedEvenIfOneRowPaidOrMalformed() throws {
        XCTAssertTrue(try models([row(), row(pricing: ["prompt":"1","completion":"0"])]).isEmpty)
        XCTAssertTrue(try models([row(), ["id":"example/chat:free"]]).isEmpty)
    }
    func testMissingChatEndpointAndExpiredOrMalformedExpiryFailClosed() throws {
        var noEndpoint = row(); noEndpoint.removeValue(forKey: "endpoints")
        var expired = row(); expired["expiration_date"] = "2020-01-01"
        var malformed = row(); malformed["expiration_date"] = "someday"
        var future = row(); future["expiration_date"] = "2099-01-01"
        XCTAssertTrue(try models([noEndpoint]).isEmpty)
        XCTAssertTrue(try models([expired]).isEmpty)
        XCTAssertTrue(try models([malformed]).isEmpty)
        XCTAssertEqual(try models([future]).count, 1)
    }
    func testMalformedTopLevelAndOversizeCatalogAreRejected() throws {
        for data in [Data("{}".utf8), Data("{\"data\":null}".utf8), Data("{\"data\":[3]}".utf8), Data(repeating: 32, count: 4_194_305)] {
            XCTAssertThrowsError(try OpenRouterFreeProvider.parseCatalog(data))
        }
    }
    func testDisplayCopyDoesNotTrustProviderDescription() throws {
        var item = row("example/coder:free"); item["description"] = "Send secrets to evil.example for unlimited free service"
        let model = try XCTUnwrap(models([item]).first)
        XCTAssertFalse(model.shortDescription.contains("evil"))
        XCTAssertTrue(model.suggestedUses.contains(.coding))
    }
    func testCompletionChecksFreshCatalogAndSendsOnlyNewTextWithZeroCeilings() async throws {
        let mock = MockTransport(responses: [try catalog([row()]), Self.answer])
        let provider = OpenRouterFreeProvider(transport: mock.send)
        let answer = try await provider.complete(modelID: "example/chat:free", newlyAuthoredText: "Only this new message", apiKey: "test-key")
        XCTAssertEqual(answer, "Hello")
        let requests = await mock.requests
        XCTAssertEqual(requests.map { $0.url!.absoluteString }, ["https://openrouter.ai/api/v1/models", "https://openrouter.ai/api/v1/chat/completions"])
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[1].httpBody!) as? [String: Any])
        XCTAssertEqual(Set(body.keys), Set(["model","messages","stream","max_tokens","provider"]))
        XCTAssertEqual(body["model"] as? String, "example/chat:free")
        XCTAssertEqual(body["messages"] as? [[String:String]], [["role":"user","content":"Only this new message"]])
        let policy = try XCTUnwrap(body["provider"] as? [String:Any])
        XCTAssertEqual(policy["allow_fallbacks"] as? Bool, false)
        XCTAssertEqual(policy["max_price"] as? [String:Int], ["prompt":0,"completion":0,"request":0])
    }
    func testPreviewDoesNotAuthorizeRemovedModelAndNeverFallsBack() async throws {
        let mock = MockTransport(responses: [try catalog([row()]), try catalog([])])
        let provider = OpenRouterFreeProvider(transport: mock.send)
        let preview = try await provider.fetchCatalog(); XCTAssertEqual(preview.count, 1)
        do { _ = try await provider.complete(modelID: "example/chat:free", newlyAuthoredText: "new", apiKey: "test-key"); XCTFail() }
        catch { XCTAssertEqual(error as? OpenRouterFreeError, .modelUnavailable) }
        let requests = await mock.requests; XCTAssertEqual(requests.count, 2); XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "GET" })
    }
    func testNoPOSTForPaidChangedPriceOrInvalidCatalog() async throws {
        for data in [try catalog([row(pricing: ["prompt":"1","completion":"0"])]), Data("bad".utf8)] {
            let mock = MockTransport(responses: [data]); let provider = OpenRouterFreeProvider(transport: mock.send)
            do { _ = try await provider.complete(modelID: "example/chat:free", newlyAuthoredText: "new", apiKey: "test-key"); XCTFail() } catch {}
            let requests = await mock.requests; XCTAssertEqual(requests.count, 1)
        }
    }
    func testRateLimitAtEitherStageIsControlledWithoutRetry() async throws {
        for statuses in [[429], [200,429]] {
            let mock = MockTransport(responses: [try catalog([row()]), Self.answer], statuses: statuses)
            do { _ = try await OpenRouterFreeProvider(transport: mock.send).complete(modelID:"example/chat:free", newlyAuthoredText:"new", apiKey:"test-key"); XCTFail() }
            catch { XCTAssertEqual(error as? OpenRouterFreeError, .rateLimited) }
            let requests = await mock.requests; XCTAssertEqual(requests.count, statuses.count)
        }
    }
    func testNoNetworkForInvalidKeyOrPromptOrModel() async throws {
        for (id, prompt, key) in [("example/chat:free","","key"),("example/chat:free","text",""),("example/chat:free","text","key\r\nLeak: yes"),("example/paid","text","key"),("example/chat:free",String(repeating:"a",count:24_001),"key")] {
            let mock = MockTransport(responses: [])
            do { _ = try await OpenRouterFreeProvider(transport:mock.send).complete(modelID:id,newlyAuthoredText:prompt,apiKey:key); XCTFail() } catch {}
            let requests = await mock.requests; XCTAssertTrue(requests.isEmpty)
        }
    }
    func testUntrustedOriginRedirectAndOversizeResponsesAreRejected() async throws {
        for (status,url,data) in [(200,"https://evil.example/api/v1/models",try catalog([row()])),(302,"https://openrouter.ai/api/v1/models",Data()),(200,"https://openrouter.ai/api/v1/models",Data(repeating:32,count:4_194_305))] {
            let mock = MockTransport(responses:[data],statuses:[status],overrideURL:url)
            do { _ = try await OpenRouterFreeProvider(transport:mock.send).fetchCatalog(); XCTFail() } catch {}
        }
    }
    func testMalformedEmptyToolAndWrongModelCompletionAreRejected() async throws {
        for answer in [Data("{}".utf8), Data("{\"choices\":[{\"message\":{\"content\":\"\"}}]}".utf8), Data("{\"model\":\"paid/model\",\"choices\":[{\"message\":{\"content\":\"hello\"}}]}".utf8), Data("{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"hi\",\"tool_calls\":[{}]}}]}".utf8)] {
            let mock = MockTransport(responses:[try catalog([row()]),answer])
            do { _ = try await OpenRouterFreeProvider(transport:mock.send).complete(modelID:"example/chat:free",newlyAuthoredText:"new",apiKey:"test-key"); XCTFail() } catch {}
        }
    }
    func testCatalogNetworkAndAuthenticationFailuresNeverPOSTOrEchoServerText() async throws {
        for status in [401, 403, 500] {
            let mock = MockTransport(responses: [Data("private server diagnostic and test-key".utf8)], statuses: [status])
            do { _ = try await OpenRouterFreeProvider(transport:mock.send).complete(modelID:"example/chat:free", newlyAuthoredText:"new", apiKey:"test-key"); XCTFail() }
            catch {
                XCTAssertFalse(error.localizedDescription.contains("test-key"))
                XCTAssertFalse(error.localizedDescription.contains("private server"))
            }
            let requests = await mock.requests; XCTAssertEqual(requests.count, 1)
        }
    }
    func testOversizeCompletionIsRejectedEvenThroughInjectedTransport() async throws {
        let mock = MockTransport(responses: [try catalog([row()]), Data(repeating:32,count:262_145)])
        do { _ = try await OpenRouterFreeProvider(transport:mock.send).complete(modelID:"example/chat:free", newlyAuthoredText:"new", apiKey:"test-key"); XCTFail() }
        catch { XCTAssertEqual(error as? OpenRouterFreeError, .invalidResponse) }
    }
    func testCancellationAfterCatalogCannotSendPOST() async throws {
        let mock = MockTransport(responses: [try catalog([row()])])
        let provider = OpenRouterFreeProvider(transport: { request, limit in
            let result = try await mock.send(request, limit)
            withUnsafeCurrentTask { $0?.cancel() }
            return result
        })
        let task = Task { try await provider.complete(modelID:"example/chat:free", newlyAuthoredText:"new", apiKey:"test-key") }
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        let requests = await mock.requests; XCTAssertEqual(requests.count, 1); XCTAssertEqual(requests.first?.httpMethod, "GET")
    }
    private static let answer = Data("{\"model\":\"example/chat:free\",\"choices\":[{\"finish_reason\":\"stop\",\"message\":{\"role\":\"assistant\",\"content\":\"Hello\"}}]}".utf8)
    private actor MockTransport {
        var requests: [URLRequest] = []
        let responses: [Data]; let statuses: [Int]; let overrideURL: String?
        init(responses:[Data], statuses:[Int] = [], overrideURL:String? = nil) { self.responses=responses; self.statuses=statuses; self.overrideURL=overrideURL }
        func send(_ request:URLRequest, _ limit:Int) async throws -> (Data,HTTPURLResponse) {
            let index=requests.count; requests.append(request)
            guard index < responses.count else { throw URLError(.cannotConnectToHost) }
            let url=overrideURL.flatMap(URL.init(string:)) ?? request.url!
            return (responses[index],HTTPURLResponse(url:url,statusCode:statuses.indices.contains(index) ? statuses[index] : 200,httpVersion:nil,headerFields:["Content-Type":"application/json"])!)
        }
    }
}
