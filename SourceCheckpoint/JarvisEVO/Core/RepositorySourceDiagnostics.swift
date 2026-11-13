import Foundation

/// Deterministic review hints, not bug findings or permission to execute source.
enum RepositorySourceDiagnostics {
    struct Hint: Identifiable, Sendable {
        let line: Int
        let kind: String
        let explanation: String
        var id: String { "\(line):\(kind)" }
    }
    static func inspect(path: String, text: String) -> [Hint] {
        guard path.hasSuffix(".swift"), text.utf8.count <= 131_072 else { return [] }
        var hints: [Hint] = []
        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if line.contains("fatalError(") || line.contains("preconditionFailure(") {
                hints.append(Hint(line: index + 1, kind: "Termination path", explanation: "Review whether this path can be reached by user input. Comments and strings may produce false positives."))
            }
            if line.contains("try!") {
                hints.append(Hint(line: index + 1, kind: "Forced try", explanation: "Review error handling; a thrown error here may terminate execution. This textual match is not proof of a bug."))
            }
            if line.contains("TODO") || line.contains("FIXME") {
                hints.append(Hint(line: index + 1, kind: "Review marker", explanation: "A source marker may describe unfinished work; confirm its current relevance."))
            }
            if hints.count >= 100 { return Array(hints.prefix(100)) }
        }
        return hints
    }
}
