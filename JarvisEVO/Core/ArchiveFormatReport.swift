import Foundation

/// Fixed local inventory categories only. Presence does not establish parsed schema
/// support, working attachments, or any association between files and messages.
enum ArchiveFormatReport {
    struct InputFile: Sendable { let relativePath: String; let bytes: Int64 }
    enum Metadata: String, CaseIterable, Hashable, Sendable {
        case legacyConversations = "Single conversation JSON present"
        case numberedConversations = "Numbered conversation JSON present"
        case legacyViewer = "Legacy viewer present"
        case currentViewer = "Current viewer present"
        case exportManifest = "Export manifest present"
        case assetNames = "Asset-name metadata present"
        case libraryFiles = "Library metadata present"
        var label: String { rawValue }
    }
    struct Summary: Sendable, Equatable {
        let retainedFiles: Int; let datFiles: Int; let supportedExtensionFiles: Int; let otherFiles: Int
        let conversationCount: Int; let messageCount: Int; let unresolvedRecords: Int
        let metadata: [Metadata]; let numberedConversationFiles: Int
    }
    enum Failure: LocalizedError {
        case invalid
        var errorDescription: String? { "The retained inventory cannot be summarized safely. No archive data was changed." }
    }
    static func summarize(files: [InputFile], conversationCount: Int, messageCount: Int, unresolvedRecords: Int) throws -> Summary {
        guard files.count <= 20_000, (0...10_000).contains(conversationCount),
              (0...500_000).contains(messageCount), (0...20_000).contains(unresolvedRecords)
        else { throw Failure.invalid }
        let supported: Set<String> = ["txt", "json", "pdf", "png", "jpg", "jpeg", "heic", "heif"]
        var seen = Set<String>(), metadata = Set<Metadata>()
        var dat = 0, supportedCount = 0, numbered = 0
        for file in files {
            try Task.checkCancellation()
            let path = file.relativePath
            // Bound before splitting, lowercasing or retaining attacker-controlled input.
            guard file.bytes >= 0, !path.isEmpty, path.utf8.count <= 4096,
                  !path.contains("\\"), !path.contains(":"),
                  path.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
            else { throw Failure.invalid }
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.count <= 255 }),
                  seen.insert(path).inserted else { throw Failure.invalid }
            let name = components[components.count - 1]
            let suffix = name.lastIndex(of: ".").map { String(name[name.index(after: $0)...]).lowercased() } ?? ""
            if suffix == "dat" { dat += 1 }
            else if supported.contains(suffix) { supportedCount += 1 }
            guard components.count == 1 else { continue }
            switch path {
            case "conversations.json": metadata.insert(.legacyConversations)
            case "chat.html": metadata.insert(.legacyViewer)
            case "index.html": metadata.insert(.currentViewer)
            case "export_manifest.json": metadata.insert(.exportManifest)
            case "conversation_asset_file_names.json": metadata.insert(.assetNames)
            case "library_files.json": metadata.insert(.libraryFiles)
            default:
                if path.hasPrefix("conversations-"), path.hasSuffix(".json") {
                    let digits = path.dropFirst("conversations-".count).dropLast(".json".count)
                    if !digits.isEmpty && digits.utf8.allSatisfy({ (48...57).contains($0) }) {
                        numbered += 1; metadata.insert(.numberedConversations)
                    }
                }
            }
        }
        return Summary(retainedFiles: files.count, datFiles: dat, supportedExtensionFiles: supportedCount,
            otherFiles: files.count - dat - supportedCount, conversationCount: conversationCount,
            messageCount: messageCount, unresolvedRecords: unresolvedRecords,
            metadata: Metadata.allCases.filter { metadata.contains($0) }, numberedConversationFiles: numbered)
    }
}
