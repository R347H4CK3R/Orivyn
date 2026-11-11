import Foundation
import PDFKit
import UniformTypeIdentifiers

/// Files are copied under random names; user-supplied paths never become local paths.
struct AttachmentService {
    static let maximumBytes = 10 * 1024 * 1024
    static let maximumExtractedCharacters = 60_000
    let directory: URL

    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func importFile(at source: URL) throws -> ChatAttachment {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let values = try source.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .contentTypeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= Self.maximumBytes else {
            throw AttachmentError.invalidSize
        }
        let type = values.contentType ?? UTType(filenameExtension: source.pathExtension)
        let isPDF = type?.conforms(to: .pdf) == true
        let isText = type?.conforms(to: .text) == true || type?.conforms(to: .json) == true
        guard isPDF || isText else { throw AttachmentError.unsupportedType }
        let id = UUID()
        let filename = id.uuidString + (isPDF ? ".pdf" : ".txt")
        let destination = directory.appendingPathComponent(filename, isDirectory: false)
        try FileManager.default.copyItem(at: source, to: destination)
        do {
            let actualSize = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard actualSize > 0, actualSize <= Self.maximumBytes else { throw AttachmentError.invalidSize }
            var extracted: String
            if isPDF {
                guard let document = PDFDocument(url: destination), !document.isLocked else { throw AttachmentError.unreadablePDF }
                extracted = ""
                for index in 0..<min(document.pageCount, 500) {
                    if let text = document.page(at: index)?.string { extracted += text + "\n" }
                    if extracted.count >= Self.maximumExtractedCharacters { break }
                }
                guard !extracted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AttachmentError.noExtractableText }
            } else {
                let data = try Data(contentsOf: destination, options: [.mappedIfSafe])
                guard let text = String(data: data, encoding: .utf8) else { throw AttachmentError.notUTF8 }
                extracted = text
            }
            if extracted.count > Self.maximumExtractedCharacters {
                extracted = String(extracted.prefix(Self.maximumExtractedCharacters)) + "\n[Attachment truncated at 60,000 characters.]"
            }
            return ChatAttachment(id: id, name: String(source.lastPathComponent.prefix(200)), relativePath: filename,
                                  mediaType: isPDF ? "application/pdf" : "text/plain", byteCount: actualSize, extractedText: extracted)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    func url(for attachment: ChatAttachment) -> URL? {
        // Validate even imported metadata before offering any attachment to the OS.
        guard !attachment.relativePath.isEmpty, attachment.relativePath == URL(fileURLWithPath: attachment.relativePath).lastPathComponent,
              !attachment.relativePath.contains(".."), !attachment.relativePath.contains("\\") else { return nil }
        let url = directory.appendingPathComponent(attachment.relativePath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func removeUnreferenced(keeping names: Set<String>) throws {
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where !names.contains(url.lastPathComponent) {
            try FileManager.default.removeItem(at: url)
        }
    }

    func removeAll() throws {
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: url)
        }
    }

    func remove(_ attachment: ChatAttachment) {
        if let url = url(for: attachment) { try? FileManager.default.removeItem(at: url) }
    }
}

enum AttachmentError: LocalizedError {
    case invalidSize, unsupportedType, unreadablePDF, noExtractableText, notUTF8
    var errorDescription: String? {
        switch self {
        case .invalidSize: return "Choose a nonempty file up to 10 MB."
        case .unsupportedType: return "Choose a PDF or UTF-8 text file. Images and other formats are not supported by the current text models."
        case .unreadablePDF: return "This PDF is locked or could not be read."
        case .noExtractableText: return "This PDF has no selectable text. Scanned PDFs need OCR before attaching."
        case .notUTF8: return "This text file is not UTF-8. Export it as UTF-8 and try again."
        }
    }
}
