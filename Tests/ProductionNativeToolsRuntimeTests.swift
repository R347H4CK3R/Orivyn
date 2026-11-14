import XCTest
import Foundation
@testable import JarvisEVO

/// Real production provider -> owned LlamaEngine -> native template/grammar/PEG.
/// No model doubles, direct C shortcut, remote inference or tool execution.
@MainActor
final class ProductionNativeToolsRuntimeTests: XCTestCase {
    func testRequiredProductionSuggestionAndReload() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["ORIVYN_REQUIRE_PRODUCTION_NATIVE_TOOLS"] == "1" else {
            throw XCTSkip("Explicit real native-tools gate is not enabled; no inference pass is claimed.")
        }
        #if !ORIVYN_NATIVE_TOOLS
        XCTFail("Required native-tools gate needs ORIVYN_NATIVE_TOOLS and the combined framework in app AND test targets.")
        #elseif !targetEnvironment(simulator)
        XCTFail("This gate requires the iOS simulator and a dedicated host fixture directory; it is not a device gate.")
        #else
        guard let path = environment["ORIVYN_NATIVE_TOOLS_MODEL_DIR"], path.hasPrefix("/"), !path.utf8.contains(0) else {
            XCTFail("Required absolute ORIVYN_NATIVE_TOOLS_MODEL_DIR is missing or invalid."); return
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        let attributes = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard attributes.isDirectory == true, attributes.isSymbolicLink != true else {
            XCTFail("The host fixture root must be a regular owned directory, not a symlink."); return
        }
        let descriptor = try XCTUnwrap(LocalModelCatalog.recommended.first { $0.id == "qwen3-1.7b-q8_0" })
        guard descriptor.sha256 == "061b54daade076b5d3362dac252678d17da8c68f07560be70818cace6590cb1a",
              descriptor.sha256 == NativeReadProposal.admittedModelSHA256,
              descriptor.byteCount == 1_834_426_016,
              descriptor.byteCount <= LocalModelStore.maximumFileBytes else {
            XCTFail("The production catalog/admission policy no longer matches the pinned test fixture."); return
        }
        // No test-bundle/model copy or import. The real store verifies the full
        // pinned file at this dedicated root before EACH provider invocation.
        // This exercises verified admission, not model installation/import UI.
        let provider = LocalAIProvider(store: try LocalModelStore(root: directory), model: descriptor)
        let start = Date()
        do {
            for pass in 1...2 {
                let proposal = try await provider.suggestNativeReads(
                    goal: "Read the reviewed application identity and installed models.",
                    validateAdmission: { try Task.checkCancellation() })
                XCTAssertTrue(proposal.appInfo, "Pass \(pass) must suggest the requested application read")
                XCTAssertTrue(proposal.installedModels, "Pass \(pass) must suggest the requested installed-model read")
                // Production async unload joins the native worker before dropping
                // resources. The next iteration must load and generate again.
                await provider.unload()
                let evidence = XCTAttachment(string: "scope=iOS simulator CPU production native-tools\npass=\(pass)\nmodelSHA256=\(descriptor.sha256)\nmodelBytes=\(descriptor.byteCount)\nappInfo=\(proposal.appInfo)\ninstalledModels=\(proposal.installedModels)\nunloadReturned=true\nelapsedSeconds=\(Date().timeIntervalSince(start))")
                evidence.name = "production-native-tools-pass-\(pass)"
                evidence.lifetime = .keepAlways; add(evidence)
            }
        } catch {
            await provider.unload()
            throw error
        }
        print("ORIVYN_PRODUCTION_NATIVE_TOOLS_GATE_COMPLETED")
        #endif
    }
}
