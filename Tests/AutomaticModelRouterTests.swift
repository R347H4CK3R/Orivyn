import XCTest
@testable import JarvisEVO

final class AutomaticModelRouterTests: XCTestCase {
    private let generalID = "qwen2.5-0.5b-instruct-q4_k_m"
    private let coderID = "qwen2.5-coder-1.5b-instruct-q4_k_m"
    private let excludedCoderID = "qwen2.5-coder-0.5b-instruct-q4_k_m"

    func testGeneralPromptChoosesPinnedSmallGeneralDownloadWithExplanation() throws {
        let decision = try AutomaticModelRouter.route(text: "Help me plan a relaxing weekend", installed: [], environment: environment())
        XCTAssertEqual(decision.model.id, "qwen2.5-0.5b-instruct-q4_k_m")
        XCTAssertEqual(decision.model.byteCount, 491_400_032)
        XCTAssertEqual(decision.purpose, "General chat")
        XCTAssertTrue(decision.needsDownload)
        XCTAssertFalse(decision.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testCodingRequestsChoosePinnedCoderWithoutRunningAnotherModel() throws {
        for prompt in ["Write a Python statement that prints 2 + 2. Return only the code.", "Write a Python function to sort a list", "Debug this JavaScript error", "Refactor this SQL query", "Build a SwiftUI view", "```swift\nlet total = 1 + 2\n```"] {
            let decision = try AutomaticModelRouter.route(text: prompt, installed: [], environment: environment())
            XCTAssertEqual(decision.model.id, coderID, prompt)
            XCTAssertEqual(decision.model.byteCount, 1_117_320_768, prompt)
            XCTAssertEqual(decision.purpose, "Coding", prompt)
            XCTAssertTrue(decision.needsDownload)
        }
    }

    func testLanguageAndProgrammingArtifactRequestsChooseCoder() throws {
        for prompt in ["Write a Python program to sort numbers", "Implement a Swift class for a shopping cart", "Create a Rust parser", "Build a Java module", "Generate Python tests for this library", "Explain this Swift method", "Write a program in Python", "Create a Python PROGRAM"] {
            XCTAssertEqual(try AutomaticModelRouter.route(text: prompt, installed: [], environment: environment()).model.id, coderID, prompt)
        }
    }

    func testNewLanguageRoutingRetainsInstalledAndDownloadSafeguards() throws {
        let prompt = "Write a Python program to sort numbers"
        let coder = try descriptor(coderID)
        let offline = try AutomaticModelRouter.route(text: prompt, installed: [coder], environment: environment(storage: nil, network: .offline))
        XCTAssertEqual(offline.model.id, coderID)
        XCTAssertFalse(offline.needsDownload)
        for (network, error) in [(AutomaticDownloadNetwork.offline, AutomaticRoutingError.offline), (.unknown, .networkUnknown), (.constrained, .constrainedNetwork), (.cellular, .cellularNotAllowed)] {
            XCTAssertThrowsError(try AutomaticModelRouter.route(text: prompt, installed: [], environment: environment(network: network))) { XCTAssertEqual($0 as? AutomaticRoutingError, error) }
        }
        XCTAssertThrowsError(try AutomaticModelRouter.route(text: prompt, installed: [coder], environment: environment(memory: 5_999_999_999))) { XCTAssertEqual($0 as? AutomaticRoutingError, .insufficientMemory) }
        XCTAssertThrowsError(try AutomaticModelRouter.route(text: prompt, installed: [], environment: environment(storage: 0))) { XCTAssertEqual($0 as? AutomaticRoutingError, .insufficientStorage) }
    }

    func testLanguageWordsAndAmbiguousArtifactsAloneDoNotTriggerCoder() throws {
        for prompt in ["Write a story about a python", "Explain a swift bird's migration", "Create a program for a dance recital", "Explain rust on my car", "Write about my Java vacation", "Plan a Python programming class", "A swift bird flew over my school class", "Write a story about a python visiting my class", "Write a report about rust for my class", "Explain a swift bird migration to my class", "Create a python exhibit for the zoo program"] {
            XCTAssertEqual(try AutomaticModelRouter.route(text: prompt, installed: [], environment: environment()).model.id, generalID, prompt)
        }
    }

    func testLexicalMatchingDoesNotConfuseIncidentalSubstringsOrEverydayWords() throws {
        for prompt in ["Decode this dream", "What is the dress code?", "Make a program for a dance recital", "Explain a swift bird's migration", "Tell me about a python at the zoo", "Transcribe my thoughts about a postcard"] {
            XCTAssertEqual(try AutomaticModelRouter.route(text: prompt, installed: [], environment: environment()).model.id, generalID, prompt)
        }
    }

    func testEmptyOrNonEnglishTextUsesGeneralFallback() throws {
        for prompt in ["", " \n", "Aide-moi à préparer mon voyage", "请帮我安排明天的计划"] {
            XCTAssertEqual(try AutomaticModelRouter.route(text: prompt, installed: [], environment: environment()).purpose, "General chat")
        }
    }

    func testRouterRejectsAboveUTF8LimitButAcceptsExactBoundary() throws {
        let text = String(repeating: "😀", count: 8_192)
        XCTAssertEqual(try AutomaticModelRouter.route(text: text, installed: [], environment: environment()).purpose, "General chat")
        XCTAssertThrowsError(try AutomaticModelRouter.route(text: text + "a", installed: [], environment: environment()))
    }

    func testInstalledGeneralModelWorksOfflineWithoutStorageInformation() throws {
        let model = try descriptor(generalID)
        let decision = try AutomaticModelRouter.route(text: "Hello", installed: [model], environment: environment(storage: nil, network: .offline))
        XCTAssertEqual(decision.model, model)
        XCTAssertFalse(decision.needsDownload)
    }

    func testInstalledMatchingModelWorksWithUnknownOrConstrainedNetwork() throws {
        for network in [AutomaticDownloadNetwork.unknown, .constrained, .cellular] {
            let decision = try AutomaticModelRouter.route(text: "Debug this function", installed: [try descriptor(coderID)], environment: environment(storage: nil, network: network))
            XCTAssertEqual(decision.model.id, coderID)
            XCTAssertFalse(decision.needsDownload)
        }
    }

    func testPrefersStrongestRAMCompatibleInstalledMatchingModelIndependentOfOrder() throws {
        let models = try [generalID, "qwen2.5-0.5b-instruct-q5_k_m", "smollm2-1.7b-instruct-q4_k_m", "qwen2.5-1.5b-instruct-q4_k_m"].map(descriptor)
        for ordered in [models, Array(models.reversed())] {
            let decision = try AutomaticModelRouter.route(text: "Plan a trip", installed: ordered, environment: environment(memory: 6_000_000_000, storage: nil, network: .offline))
            XCTAssertEqual(decision.model.id, "qwen2.5-1.5b-instruct-q4_k_m")
            XCTAssertFalse(decision.needsDownload)
        }
    }

    func testLowRAMSkipsLargerInstalledModelRatherThanLoadingIt() throws {
        let models = try [generalID, "qwen2.5-1.5b-instruct-q4_k_m"].map(descriptor)
        let decision = try AutomaticModelRouter.route(text: "Hello", installed: models, environment: environment(memory: 5_999_999_999, network: .offline))
        XCTAssertEqual(decision.model.id, generalID)
        XCTAssertFalse(decision.needsDownload)
    }

    func testBelowMinimumRAMDoesNotAutomaticallyLoadOrDownload() throws {
        for installed in [[], [try descriptor(generalID)]] {
            XCTAssertThrowsError(try AutomaticModelRouter.route(text: "Hello", installed: installed, environment: environment(memory: 3_999_999_999)))
        }
    }

    func testGeneralInstalledModelDoesNotMasqueradeAsMatchingCoder() throws {
        let decision = try AutomaticModelRouter.route(text: "Debug this JavaScript function", installed: [try descriptor(generalID)], environment: environment())
        XCTAssertEqual(decision.model.id, coderID)
        XCTAssertTrue(decision.needsDownload)
    }

    func testInstalledCoderIsUsedInsteadOfDownloadingAnotherQuantization() throws {
        let decision = try AutomaticModelRouter.route(text: "Refactor this code", installed: [try descriptor("qwen2.5-coder-1.5b-instruct-q4_k_m")], environment: environment(memory: 6_000_000_000, storage: nil, network: .offline))
        XCTAssertEqual(decision.model.id, "qwen2.5-coder-1.5b-instruct-q4_k_m")
        XCTAssertFalse(decision.needsDownload)
    }

    func testExperimentalReasoningModelsDoNotBecomeAutomaticCandidates() throws {
        let models = try ["qwen3-0.6b-q8_0", "qwen3-1.7b-q8_0"].map(descriptor)
        let decision = try AutomaticModelRouter.route(text: "Reason step by step about this puzzle", installed: models, environment: environment(memory: 8_000_000_000))
        XCTAssertEqual(decision.model.id, generalID)
        XCTAssertTrue(decision.needsDownload)
    }

    func testImportedRemoteOrAppleLookalikesCannotBecomeAutomaticCandidates() throws {
        let canonical = try descriptor(generalID)
        let lookalikes = ["imported-user-choice", "remote", "apple-system"].map {
            LocalModelDescriptor(id: $0, name: canonical.name, fileName: canonical.fileName, downloadURL: canonical.downloadURL,
                                 sha256: canonical.sha256, byteCount: canonical.byteCount, license: canonical.license, sourceURL: canonical.sourceURL)
        }
        let decision = try AutomaticModelRouter.route(text: "Hello", installed: lookalikes, environment: environment())
        XCTAssertEqual(decision.model.id, generalID)
        XCTAssertTrue(decision.needsDownload)
    }

    func testSameIDWithWrongHashSizeOrFileNameIsNotReportedInstalled() throws {
        let canonical = try descriptor(generalID)
        let mismatched = [
            changed(canonical, hash: String(repeating: "a", count: 64)),
            changed(canonical, size: canonical.byteCount - 1),
            changed(canonical, fileName: "different-file.gguf")
        ]
        for model in mismatched {
            let decision = try AutomaticModelRouter.route(text: "Hello", installed: [model], environment: environment())
            XCTAssertEqual(decision.model, canonical)
            XCTAssertTrue(decision.needsDownload)
        }
    }

    func testUnknownStorageOrInsufficientDiskBlocksDownload() {
        let capacities: [Int64?] = [nil, 0, 1_082_800_063]
        for storage in capacities {
            XCTAssertThrowsError(try AutomaticModelRouter.route(text: "Hello", installed: [], environment: environment(storage: storage)))
        }
        XCTAssertNoThrow(try AutomaticModelRouter.route(text: "Hello", installed: [], environment: environment(storage: 1_082_800_064)))
    }

    func testUnknownOfflineAndConstrainedNetworksNeverStartAutomaticDownload() {
        for network in [AutomaticDownloadNetwork.unknown, .offline, .constrained] {
            for cellular in [false, true] {
                XCTAssertThrowsError(try AutomaticModelRouter.route(text: "Hello", installed: [], environment: environment(network: network, cellular: cellular)))
            }
        }
    }

    func testCellularDownloadRequiresExplicitChoiceAndWiFiDoesNot() throws {
        XCTAssertThrowsError(try AutomaticModelRouter.route(text: "Hello", installed: [], environment: environment(network: .cellular)))
        XCTAssertTrue(try AutomaticModelRouter.route(text: "Hello", installed: [], environment: environment(network: .cellular, cellular: true)).needsDownload)
        XCTAssertTrue(try AutomaticModelRouter.route(text: "Hello", installed: [], environment: environment(network: .wifi)).needsDownload)
    }

    func testConfirmedUnmeteredEthernetAllowsAutomaticDownload() throws {
        let decision = try AutomaticModelRouter.route(text: "Hello", installed: [], environment: environment(network: .wired))
        XCTAssertEqual(decision.model.id, generalID)
        XCTAssertTrue(decision.needsDownload)
    }

    func testAllAutomaticDownloadChoicesStayInsideSmallPinnedAllowlist() throws {
        for prompt in ["Hello", "Debug a function", "Solve this equation", "Open a website"] {
            let decision = try AutomaticModelRouter.route(text: prompt, installed: [], environment: environment(memory: 32_000_000_000))
            XCTAssertTrue([generalID, coderID].contains(decision.model.id))
            XCTAssertLessThanOrEqual(decision.model.byteCount, 1_200_000_000)
            XCTAssertEqual(AutomaticModelRouter.maximumDownloadBytes, 1_200_000_000)
            XCTAssertNotNil(decision.model.downloadURL)
        }
    }

    func testInstalledFailingSmallCoderNeverBecomesAutomaticChoice() throws {
        let small = try descriptor(excludedCoderID)
        let decision = try AutomaticModelRouter.route(text: "Debug this function", installed: [small], environment: environment())
        XCTAssertEqual(decision.model.id, coderID)
        XCTAssertTrue(decision.needsDownload)
        XCTAssertThrowsError(try AutomaticModelRouter.route(text: "Debug this function", installed: [small], environment: environment(network: .offline))) {
            XCTAssertEqual($0 as? AutomaticRoutingError, .offline)
        }
    }

    func testCodingRequiresSixGBEvenWithInstalledModels() throws {
        for installed in [[], [try descriptor(excludedCoderID)], [try descriptor(coderID)]] {
            XCTAssertThrowsError(try AutomaticModelRouter.route(text: "Debug this function", installed: installed,
                environment: environment(memory: 5_999_999_999))) {
                XCTAssertEqual($0 as? AutomaticRoutingError, .insufficientMemory)
            }
        }
        XCTAssertNoThrow(try AutomaticModelRouter.route(text: "Debug this function", installed: [], environment: environment(memory: 6_000_000_000)))
    }

    func testCodingStorageBoundaryDoesNotFallBackToSmallInstalledCoder() throws {
        let installed = [try descriptor(excludedCoderID)]
        XCTAssertThrowsError(try AutomaticModelRouter.route(text: "Debug this function", installed: installed,
            environment: environment(storage: 2_334_641_535))) {
            XCTAssertEqual($0 as? AutomaticRoutingError, .insufficientStorage)
        }
        XCTAssertTrue(try AutomaticModelRouter.route(text: "Debug this function", installed: installed,
            environment: environment(storage: 2_334_641_536)).needsDownload)
    }

    func testCodingRetainsNetworkRestrictionsAndCellularOptIn() throws {
        for network in [AutomaticDownloadNetwork.unknown, .offline, .constrained, .cellular] {
            XCTAssertThrowsError(try AutomaticModelRouter.route(text: "Debug this function", installed: [], environment: environment(network: network)))
        }
        XCTAssertTrue(try AutomaticModelRouter.route(text: "Debug this function", installed: [],
            environment: environment(network: .cellular, cellular: true)).needsDownload)
    }

    func testEligibleInstalledCoderWinsRegardlessOfExcludedSmallCoderOrder() throws {
        let models = try [excludedCoderID, coderID].map(descriptor)
        for ordered in [models, Array(models.reversed())] {
            let decision = try AutomaticModelRouter.route(text: "Debug this function", installed: ordered,
                environment: environment(storage: nil, network: .offline))
            XCTAssertEqual(decision.model.id, coderID)
            XCTAssertFalse(decision.needsDownload)
        }
    }

    private func environment(memory: UInt64 = 6_000_000_000, storage: Int64? = 4_000_000_000,
                             network: AutomaticDownloadNetwork = .wifi, cellular: Bool = false) -> AutomaticRouteEnvironment {
        AutomaticRouteEnvironment(physicalMemory: memory, freeStorageBytes: storage, network: network, allowsCellular: cellular)
    }
    private func descriptor(_ id: String) throws -> LocalModelDescriptor {
        try XCTUnwrap(LocalModelCatalog.entries.first(where: { $0.id == id })?.descriptor)
    }
    private func changed(_ model: LocalModelDescriptor, hash: String? = nil, size: Int64? = nil, fileName: String? = nil) -> LocalModelDescriptor {
        LocalModelDescriptor(id: model.id, name: model.name, fileName: fileName ?? model.fileName, downloadURL: model.downloadURL,
                             sha256: hash ?? model.sha256, byteCount: size ?? model.byteCount, license: model.license, sourceURL: model.sourceURL)
    }
}
