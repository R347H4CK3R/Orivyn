import Foundation

// Linux has no ImageIO. Only this input boundary is substituted with generated
// owned RGB; the pair actor, native adapter, worker, session and C runtime below
// are the production implementations. Test directory was hash-verified outside
// this harness and is immutable for the run; no production verifier claim here.
struct OwnedRGB: Sendable { let width: Int; let height: Int; let bytes: Data }
enum ImageBoundary {
    static func decode(_ data: Data) throws -> OwnedRGB {
        try VisionPixelBoundary.validate(width:384,height:384,rgb:data)
        return OwnedRGB(width:384,height:384,bytes:data)
    }
}
struct VerifiedFixtureFiles: VisionPairFileStore {
    let root: URL
    func verify(_ artifact: VisionModelArtifact) async throws -> URL { root.appendingPathComponent(artifact.name) }
    func download(_ artifact: VisionModelArtifact, progress: @escaping @Sendable (Double) -> Void) async throws { throw CocoaError(.featureUnsupported) }
}
@MainActor final class LeaseOwner: VisionLeaseOwner {
    var heavyWorkLease: LocalHeavyWorkLease?
    func beginHeavyWork(id: UUID, kind: LocalHeavyWorkKind) async throws { heavyWorkLease = .init(id:id,kind:kind,phase:.ready) }
    func endHeavyWork(id: UUID) { if heavyWorkLease?.id == id { heavyWorkLease = nil } }
    func revokeHeavyWork(id: UUID?) { if heavyWorkLease?.id == id { heavyWorkLease?.phase = .revoked } }
}
@main struct Test {
    @MainActor static func main() async throws {
        let store = VisionPairStore(files:VerifiedFixtureFiles(root:URL(fileURLWithPath:CommandLine.arguments[1])))
        let runtime = try NativeVisionRuntime(store:store)
        let owner = LeaseOwner(), session = VisionSession(owner:LeaseOwner(),runtime:try NativeVisionRuntime(store:store))
        // Exact production no-detail check must reject before model acquisition.
        await session.run(encodedImage:Data(repeating:255,count:384*384*3),question:"Describe the visible image in one sentence.")
        precondition(session.output == nil && session.error != nil)
        let live = VisionSession(owner:owner,runtime:runtime)
        var pixels = Data(repeating:255,count:384*384*3)
        for y in 72..<312 { for x in 72..<312 { let i=(y*384+x)*3;pixels[i+1]=0;pixels[i+2]=0 } }
        await live.run(encodedImage:pixels,question:"Describe the visible image in one sentence.")
        let answer = live.output ?? "NO OUTPUT"
        precondition(answer.lowercased().contains("red") && answer.lowercased().contains("square"),answer)
        precondition(owner.heavyWorkLease == nil && live.phase == .finished)
        let reacquired = try await store.acquire();await store.release(reacquired)
        print("PASS exact production Session → pair owner → NativeVisionRuntime → VisionWorker → actual C inference and cleanup")
        print("ACTUAL OUTPUT: \(answer)")
    }
}
