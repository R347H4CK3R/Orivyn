import XCTest
import Foundation
@testable import JarvisEVO

/// Explicit fixture pins independent of the generated catalog; never accepts an arbitrary descriptor.
enum ProductionModelFixture {
    static func descriptor(environment: [String: String]) throws -> LocalModelDescriptor {
        let id = environment["ORIVYN_PRODUCTION_MODEL_ID"] ?? "qwen3-1.7b-q8_0"
        let pin: (String, String, Int64, NativeReadPolicy)
        switch id {
        case "qwen3-1.7b-q8_0":
            pin = ("Qwen3-1.7B-Q8_0.gguf", "061b54daade076b5d3362dac252678d17da8c68f07560be70818cace6590cb1a", 1_834_426_016, .q8)
        case "qwen3-1.7b-q4_k_m":
            pin = ("Qwen3-1.7B-Q4_K_M.gguf", "d2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5", 1_282_439_264, .q4Candidate)
        default:
            XCTFail("Unknown required production model ID")
            throw LocalModelError.invalidDescriptor
        }
        let descriptor = try XCTUnwrap(LocalModelCatalog.recommended.first { $0.id == id })
        guard descriptor.fileName == pin.0, descriptor.sha256 == pin.1, descriptor.byteCount == pin.2,
              descriptor.byteCount <= LocalModelStore.maximumFileBytes,
              NativeReadProposal.policy(forVerifiedSHA256: descriptor.sha256) == pin.3 else {
            XCTFail("Production catalog/admission no longer matches the exact fixture pin")
            throw LocalModelError.invalidDescriptor
        }
        return descriptor
    }
}
