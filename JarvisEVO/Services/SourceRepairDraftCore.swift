import Foundation
import CryptoKit
import JavaScriptCore

/// Creates a local change preview only. No API client, signing, build or execution.
@MainActor
final class SourceRepairDraftCore {
    struct Draft: Decodable {
        let status: String
        let path: String
        let commitSHA: String
        let blobSHA: String
        let summary: String
        let diff: String
        let checks: [String]
        let limitations: [String]
    }
    private let context: JSContext
    private let api: JSValue
    init(bundle: Bundle = .main) throws {
        guard let url = bundle.url(forResource: "SourceRepairDraft", withExtension: "js"),
              let data = try? Data(contentsOf: url), data.count <= 100_000,
              let source = String(data: data, encoding: .utf8), let context = JSContext() else { throw LocalAgentError.unavailable }
        context.evaluateScript(source)
        guard context.exception == nil, let api = context.objectForKeyedSubscript("OrivynSourceRepairDraft"), !api.isUndefined else { throw LocalAgentError.unavailable }
        self.context = context; self.api = api
    }
    func create(file: RepositoryInspectionFile, replacement: String, summary: String) throws -> Draft {
        let original = Data(file.text.utf8)
        guard original.count <= 131_072, replacement.utf8.count <= 131_072, summary.utf8.count <= 500 else { throw RepositoryInspectionError.bounds }
        var gitBlob = Data("blob \(original.count)\0".utf8); gitBlob.append(original)
        let hash = Insecure.SHA1.hash(data: gitBlob).map { String(format: "%02x", $0) }.joined()
        guard hash == file.blobSHA else { throw RepositoryInspectionError.integrity }
        let object: [String: String] = ["path": file.path, "commitSHA": file.commitSHA, "blobSHA": file.blobSHA, "originalText": file.text, "replacementText": replacement, "summary": summary]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard data.count <= 1_600_000, let input = String(data: data, encoding: .utf8) else { throw RepositoryInspectionError.bounds }
        context.exception = nil
        guard let function = api.forProperty("create"), !function.isUndefined,
              let value = function.call(withArguments: [input]), context.exception == nil,
              value.isString, let output = value.toString(), output.utf8.count <= 2_000_000 else { throw LocalAgentError.invalidState }
        let draft = try JSONDecoder().decode(Draft.self, from: Data(output.utf8))
        guard draft.status == "draftNotApplied", draft.path == file.path, draft.commitSHA == file.commitSHA, draft.blobSHA == file.blobSHA else { throw RepositoryInspectionError.integrity }
        return draft
    }
}
