import Foundation
import Glibc

// Controlled asynchronous storage boundary only: no network or installed models.
actor ControlledModelStore {
    var callbacks: [@Sendable (Double) -> Void] = []
    var waits: [CheckedContinuation<Void, any Error>] = []
    func download(_ descriptor: LocalModelDescriptor, progress: @escaping @Sendable (Double) -> Void) async throws {
        callbacks.append(progress)
        try await withCheckedThrowingContinuation { waits.append($0) }
    }
    func count() -> Int { callbacks.count }
    func emit(_ index: Int, _ progress: Double) { callbacks[index](progress) }
    func finish(_ index: Int, cancelled: Bool = false) {
        if cancelled { waits[index].resume(throwing: CancellationError()) }
        else { waits[index].resume() }
    }
}
@MainActor final class DownloadScaffold {
    let modelStore = ControlledModelStore()
    var isPreparingAutomaticModel = false
    var automaticDownloadOwner: UUID?
    var manualDownloadOwner: UUID?
    var downloadTask: Task<Void, Never>?
    var downloadingModelID: String?
    var downloadProgress: Double?
    var selectedProviderID = ""
    var errors = 0
    var reloads = 0
    var suspendReload = false
    var reloadWait: CheckedContinuation<Void, Never>?
    func reloadProviders() async throws {
        reloads += 1
        if suspendReload { await withCheckedContinuation { reloadWait = $0 } }
    }
    func report(_ error: any Error) { errors += 1 }
    func cancelAutomaticPreparation() { automaticDownloadOwner = nil }
    // PRODUCTION_METHODS
}
@main struct ModelDownloadSmoke {
    @MainActor static func settle() async { for _ in 0..<50 { await Task.yield() }; try? await Task.sleep(for: .milliseconds(10)) }
    @MainActor static func main() async throws {
        let model = DownloadScaffold()
        let descriptor = LocalModelDescriptor(id: "same", name: "Fixture", fileName: "fixture.gguf", downloadURL: nil, sha256: String(repeating: "a", count: 64), byteCount: 1, license: "fixture", sourceURL: nil)
        var checks: [[String: Any]] = []
        model.downloadModel(descriptor); await settle()
        await model.modelStore.emit(0, 0.4); await settle()
        checks.append(["check":"current progress accepted", "passed":model.downloadProgress == 0.4])
        await model.modelStore.finish(0); await settle()
        checks.append(["check":"success clears task and selects model", "passed":model.downloadTask == nil && model.downloadProgress == nil && model.selectedProviderID == descriptor.id])
        await model.modelStore.emit(0, 0.8); await settle()
        checks.append(["check":"late callback cannot resurrect completed progress", "passed":model.downloadProgress == nil])
        model.downloadModel(descriptor); await settle()
        await model.modelStore.emit(1, 0.2); await settle()
        await model.modelStore.emit(0, 0.9); await settle()
        checks.append(["check":"previous same-model owner cannot overwrite new progress", "passed":model.downloadProgress == 0.2])
        model.cancelDownload()
        checks.append(["check":"cancel signals active task", "passed":model.downloadTask?.isCancelled == true])
        await model.modelStore.finish(1, cancelled: true); await settle()
        await model.modelStore.emit(1, 0.7); await settle()
        checks.append(["check":"cancelled completion stays cleared without reporting error", "passed":model.downloadTask == nil && model.downloadProgress == nil && model.errors == 0])
        let late = DownloadScaffold()
        late.selectedProviderID = "existing-provider"
        late.suspendReload = true
        late.downloadModel(descriptor); await settle()
        await late.modelStore.finish(0); await settle()
        guard let waitingReload = late.reloadWait else { fatalError("Download did not reach reload boundary") }
        late.cancelDownload()
        waitingReload.resume(); await settle()
        checks.append(["check":"late cancellation skips explicit model selection and still clears task", "passed":late.reloads == 1 && late.selectedProviderID == "existing-provider" && late.downloadTask == nil && late.downloadingModelID == nil && late.downloadProgress == nil && late.errors == 0])
        print(String(decoding: try JSONSerialization.data(withJSONObject: ["checks":checks,"nativeVerified":false,"networkUsed":false], options: [.prettyPrinted,.sortedKeys]), as: UTF8.self))
        if checks.contains(where: { $0["passed"] as? Bool != true }) { exit(1) }
    }
}
