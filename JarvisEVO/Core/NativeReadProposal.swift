import Foundation

struct NativeReadProposal: Sendable {
    let appInfo: Bool
    let installedModels: Bool
    static let admittedModelSHA256 = "061b54daade076b5d3362dac252678d17da8c68f07560be70818cace6590cb1a"
    static func parse(_ text: String) throws -> Self {
        struct Envelope: Decodable {
            struct Read: Decodable { let name: String; let arguments: [String: String]; let session_sequence: Int }
            let state: String; let reserved_reads: [Read]
        }
        guard text.utf8.count <= 4096 else { throw LocalAgentError.outputBound }
        let value = try JSONDecoder().decode(Envelope.self, from: Data(text.utf8))
        guard value.state == "reserved_not_executed", (1...2).contains(value.reserved_reads.count) else { throw LocalAgentError.invalidState }
        var names = Set<String>()
        for (index, read) in value.reserved_reads.enumerated() {
            guard ["get_app_info", "list_models"].contains(read.name), read.arguments.isEmpty,
                  read.session_sequence == index + 1, names.insert(read.name).inserted else { throw LocalAgentError.invalidState }
        }
        return Self(appInfo: names.contains("get_app_info"), installedModels: names.contains("list_models"))
    }
}

/// Cancellation can arrive before a task is installed. Observation callbacks use
/// this synchronously, so a revoked lease cannot wait for a UI refresh to cancel.
final class NativeReadCancellationRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var action: (@Sendable () -> Void)?
    func install(_ action: @escaping @Sendable () -> Void) {
        lock.lock()
        let run = cancelled
        if !run { self.action = action }
        lock.unlock()
        if run { action() }
    }
    func cancel() {
        lock.lock(); cancelled = true
        let action = self.action; self.action = nil
        lock.unlock(); action?()
    }
    func finish() { lock.lock(); action = nil; lock.unlock() }
}
