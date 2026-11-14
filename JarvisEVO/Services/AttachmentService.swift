import Foundation
import PDFKit
import UniformTypeIdentifiers

/// Files are copied under random names; user-supplied paths never become local paths.
struct AttachmentService: Sendable {
    static let maximumBytes = 10 * 1024 * 1024
    static let maximumExtractedCharacters = 60_000
    let directory: URL
    private let imageService: ImageAttachmentService

    init(directory: URL) throws {
        imageService = try ImageAttachmentService(directory: directory)
        self.directory = imageService.directory
    }

    func importFile(at source: URL) throws -> ChatAttachment {
        try Task.checkCancellation()
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let values = try source.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey, .contentTypeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize, size > 0, size <= Self.maximumBytes else {
            throw AttachmentError.invalidSize
        }
        let type = values.contentType ?? UTType(filenameExtension: source.pathExtension)
        if type?.conforms(to: .image) == true { return chatAttachment(from: try imageService.importFile(at: source)) }
        let isPDF = type?.conforms(to: .pdf) == true
        let isText = type?.conforms(to: .text) == true || type?.conforms(to: .json) == true
        guard isPDF || isText else { throw AttachmentError.unsupportedType }
        let id = UUID()
        let filename = id.uuidString + (isPDF ? ".pdf" : ".txt")
        let destination = directory.appendingPathComponent(filename, isDirectory: false)
        let actualSize = try AttachmentFileCopy.copy(from: source, to: destination, maximumBytes: Self.maximumBytes)
        do {
            var extracted: String
            if isPDF {
                guard let document = PDFDocument(url: destination), !document.isLocked else { throw AttachmentError.unreadablePDF }
                extracted = try PDFTextExtractor.extract(document: document)
            } else {
                let data = try Data(contentsOf: destination, options: [.mappedIfSafe])
                guard let text = String(data: data, encoding: .utf8) else { throw AttachmentError.notUTF8 }
                extracted = text
            }
            if extracted.count > Self.maximumExtractedCharacters {
                extracted = String(extracted.prefix(Self.maximumExtractedCharacters)) + "\n[Attachment truncated at 60,000 characters.]"
            }
            try Task.checkCancellation()
            return ChatAttachment(id: id, name: String(source.lastPathComponent.prefix(200)), relativePath: filename,
                                  mediaType: isPDF ? "application/pdf" : "text/plain", byteCount: actualSize, extractedText: extracted)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    func importImage(data: Data, suggestedName: String) throws -> ChatAttachment {
        chatAttachment(from: try imageService.importData(data, suggestedName: suggestedName))
    }

    private func chatAttachment(from image: ImportedImageAttachment) -> ChatAttachment {
        ChatAttachment(id: image.id, name: image.name, relativePath: image.relativePath, mediaType: image.mediaType,
                       byteCount: image.byteCount, extractedText: image.textModelContext, previewRelativePath: image.previewRelativePath)
    }

    func url(for attachment: ChatAttachment) -> URL? {
        guard attachment.hasValidStorageBinding else { return nil }
        if attachment.isImage { return imageService.trustedOriginalURL(for: attachment) }
        return url(forRelativePath: attachment.relativePath)
    }

    func previewURL(for attachment: ChatAttachment) -> URL? {
        imageService.trustedPreviewURL(for: attachment)
    }

    private func url(forRelativePath path: String) -> URL? {
        // Validate even imported metadata before offering any attachment to the OS.
        guard ChatAttachment.isSafeRelativePath(path) else { return nil }
        let url = directory.appendingPathComponent(path, isDirectory: false)
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink == false else { return nil }
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.deletingLastPathComponent().path == root.path else { return nil }
        return url
    }

    func removeUnreferenced(keeping names: Set<String>) throws {
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where !names.contains(url.lastPathComponent) {
            try FileManager.default.removeItem(at: url)
        }
        try imageService.removeUnreferencedProvenance(keeping: names)
    }

    func removeAll() throws {
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: url)
        }
        try imageService.removeUnreferencedProvenance(keeping: [])
    }

    func remove(_ attachment: ChatAttachment) {
        guard attachment.hasValidStorageBinding else { return }
        if attachment.isImage { imageService.removeOwnedImage(attachment); return }
        for path in attachment.localRelativePaths {
            if let url = url(forRelativePath: path) { try? FileManager.default.removeItem(at: url) }
        }
    }
}

enum AttachmentImportSource: Sendable {
    case file(URL)
    case image(data: Data, suggestedName: String)
}

/// An importer owns new files until it returns them; throwing must not leave an unreported file behind.
protocol AttachmentImporting: Sendable {
    func importAttachment(_ source: AttachmentImportSource) async throws -> ChatAttachment
}

/// Serial actor isolation keeps decoding, PDF extraction and Vision work off the main actor.
actor LocalAttachmentImporter: AttachmentImporting {
    private let service: AttachmentService
    init(service: AttachmentService) { self.service = service }
    func importAttachment(_ source: AttachmentImportSource) async throws -> ChatAttachment {
        try Task.checkCancellation()
        switch source {
        case .file(let url): return try service.importFile(at: url)
        case .image(let data, let suggestedName): return try service.importImage(data: data, suggestedName: suggestedName)
        }
    }
}

enum AttachmentError: LocalizedError {
    case invalidSize, unsupportedType, unreadablePDF, noExtractableText, notUTF8
    var errorDescription: String? {
        switch self {
        case .invalidSize: return "Choose a nonempty file up to 10 MB."
        case .unsupportedType: return "Choose a PDF, UTF-8 text file, or JPEG, PNG, HEIC, or HEIF image. Images provide recognized text only to current models."
        case .unreadablePDF: return "This PDF is locked or could not be read."
        case .noExtractableText: return "No text could be extracted or recognized from this PDF. Inspect the original; absence of recognized text does not prove it is blank."
        case .notUTF8: return "This text file is not UTF-8. Export it as UTF-8 and try again."
        }
    }
}
