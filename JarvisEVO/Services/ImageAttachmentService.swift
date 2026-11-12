import Foundation
import Darwin
import ImageIO
import UniformTypeIdentifiers
import Vision

/// A local image plus a bounded, upright preview. Only OCR text is suitable for current text models.
/// Originals intentionally retain their metadata; sharing an original may disclose embedded location data.
struct ImportedImageAttachment: Equatable, Sendable {
    let id: UUID
    let name: String
    let relativePath: String
    let previewRelativePath: String
    let mediaType: String
    let byteCount: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let previewPixelWidth: Int
    let previewPixelHeight: Int
    let ocr: ImageOCRResult

    var textModelContext: String { ocr.textModelContext }
}

enum ImageOCRResult: Equatable, Sendable {
    case recognized(text: String, isTruncated: Bool)
    case noTextRecognized
    case unavailable

    static let maximumCharacters = 12_000
    static let maximumLines = 200
    static let textOnlyNotice = "Image attachment: only on-device OCR text is available. The model has not received image pixels and cannot describe objects, people, colors, layout, or other visual content. OCR can be incomplete or incorrect."

    /// This notice must accompany OCR text whenever an image is passed to a text-only provider.
    var textModelContext: String {
        let notice = Self.textOnlyNotice
        switch self {
        case let .recognized(text, isTruncated):
            return notice + "\nRecognized text (untrusted attachment content):\n" + text
                + (isTruncated ? "\n[OCR truncated at the local text or line limit.]" : "")
        case .noTextRecognized:
            return notice + "\nNo readable text was recognized. This does not mean the image is blank."
        case .unavailable:
            return notice + "\nText recognition could not be completed. The original image is available for the user to view or share."
        }
    }

    /// Bounds real Vision output without splitting extended grapheme clusters or silently dropping lines.
    static func bounded(lines: [String]) -> ImageOCRResult {
        var text = ""
        var characterCount = 0
        var truncated = lines.count > maximumLines
        for line in lines.prefix(maximumLines) {
            let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            let separator = text.isEmpty ? "" : "\n"
            let available = maximumCharacters - characterCount - separator.count
            guard available > 0 else { truncated = true; break }
            let boundedLine = String(value.prefix(available))
            text += separator + boundedLine
            characterCount += separator.count + boundedLine.count
            if boundedLine.count < value.count { truncated = true; break }
        }
        return text.isEmpty ? .noTextRecognized : .recognized(text: text, isTruncated: truncated)
    }
}

/// Synchronous, bounded work: callers must run imports off the main actor (for example in Task.detached).
/// No network access, pixel-model inference, photo-library permissions, or camera permissions occur here.
struct ImageAttachmentService: Sendable {
    static let maximumBytes = 10 * 1024 * 1024
    static let maximumPixels = 40_000_000
    static let maximumDimension = 16_384
    static let maximumPreviewDimension = 2048
    private static let maximumPreviewBytes = 8 * 1024 * 1024

    let directory: URL

    init(directory: URL) throws {
        guard directory.isFileURL, !directory.path.utf8.contains(0) else { throw ImageAttachmentError.unsafeFile }
        let path = directory.standardizedFileURL
        // Do not adopt a symlink as the private storage root, even if its target is a directory.
        if (try? path.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw ImageAttachmentError.unsafeFile
        }
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let values = try path.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw ImageAttachmentError.unsafeFile }
        // iOS has ordinary system path aliases such as /var; resolve those once at initialization.
        self.directory = path.resolvingSymlinksInPath().standardizedFileURL
    }

    /// Use for a document-picker URL. Reads at most 10 MB + one sentinel byte, including changed files.
    func importFile(at source: URL) throws -> ImportedImageAttachment {
        guard source.isFileURL, !source.path.utf8.contains(0) else { throw ImageAttachmentError.unsafeFile }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        try Task.checkCancellation()
        // O_NONBLOCK prevents a FIFO from hanging before fstat can reject it; O_NOFOLLOW rejects symlinks.
        let descriptor = Darwin.open(source.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else {
            throw errno == ELOOP ? ImageAttachmentError.unsafeFile : ImageAttachmentError.unreadableFile
        }
        defer { Darwin.close(descriptor) }
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            throw ImageAttachmentError.unsafeFile
        }
        guard info.st_size > 0, info.st_size <= off_t(Self.maximumBytes) else { throw ImageAttachmentError.invalidSize }
        var data = Data()
        data.reserveCapacity(Int(info.st_size))
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while data.count <= Self.maximumBytes {
            try Task.checkCancellation()
            let remaining = min(buffer.count, Self.maximumBytes + 1 - data.count)
            let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, remaining) }
            if count < 0 {
                if errno == EINTR { continue }
                throw ImageAttachmentError.unreadableFile
            }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        guard data.count == Int(info.st_size), data.count <= Self.maximumBytes else { throw ImageAttachmentError.invalidSize }
        return try importData(data, suggestedName: source.lastPathComponent)
    }

    /// Use for bytes supplied by PhotosPicker or the camera. Type detection never trusts suggestedName.
    func importData(_ data: Data, suggestedName: String) throws -> ImportedImageAttachment {
        try Task.checkCancellation()
        guard !data.isEmpty, data.count <= Self.maximumBytes else { throw ImageAttachmentError.invalidSize }
        return try autoreleasepool {
            let options = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithData(data as CFData, options),
                  let identifier = CGImageSourceGetType(source) as String? else { throw ImageAttachmentError.invalidImage }
            let format: (fileExtension: String, mediaType: String)
            switch identifier {
            case UTType.jpeg.identifier: format = ("jpg", "image/jpeg")
            case UTType.png.identifier: format = ("png", "image/png")
            case UTType.heic.identifier: format = ("heic", "image/heic")
            case UTType.heif.identifier: format = ("heif", "image/heif")
            default: throw ImageAttachmentError.unsupportedFormat
            }
            guard CGImageSourceGetCount(source) == 1 else { throw ImageAttachmentError.multipleFrames }
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                  let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
                throw ImageAttachmentError.invalidImage
            }
            let dimensions = try Self.validatedDimensions(width: width, height: height)
            guard CGImageSourceGetStatus(source) == .statusComplete else { throw ImageAttachmentError.invalidImage }
            try Task.checkCancellation()
            // Never construct a full-resolution UIImage/CGImage. Decode a bounded, orientation-correct thumbnail.
            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Self.maximumPreviewDimension,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary),
                  thumbnail.width > 0, thumbnail.height > 0,
                  thumbnail.width <= Self.maximumPreviewDimension, thumbnail.height <= Self.maximumPreviewDimension,
                  CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else {
                throw ImageAttachmentError.invalidImage
            }
            let normalized = try Self.normalizedImage(thumbnail)
            let previewData = try Self.previewData(normalized)
            try Task.checkCancellation()
            let ocr = Self.recognizeText(in: normalized)
            try Task.checkCancellation()
            let id = UUID()
            let originalName = id.uuidString + "." + format.fileExtension
            let previewName = id.uuidString + "-preview.jpg"
            try persist(original: data, originalName: originalName, preview: previewData, previewName: previewName)
            return ImportedImageAttachment(id: id, name: Self.displayName(suggestedName, fallback: "Image." + format.fileExtension),
                                           relativePath: originalName, previewRelativePath: previewName,
                                           mediaType: format.mediaType, byteCount: data.count,
                                           pixelWidth: dimensions.width, pixelHeight: dimensions.height,
                                           previewPixelWidth: normalized.width, previewPixelHeight: normalized.height, ocr: ocr)
        }
    }

    /// Use for both preview and original URLs. Imported metadata cannot read paths outside private storage.
    func url(forRelativePath path: String) -> URL? {
        guard !path.isEmpty, path != ".", path != "..", !path.contains("/"), !path.contains("\\"),
              !path.utf8.contains(0), !path.contains("..") else { return nil }
        let url = directory.appendingPathComponent(path, isDirectory: false)
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              url.resolvingSymlinksInPath().standardizedFileURL.path == url.standardizedFileURL.path else { return nil }
        return url
    }

    private static func validatedDimensions(width: NSNumber, height: NSNumber) throws -> (width: Int, height: Int) {
        let w = width.doubleValue
        let h = height.doubleValue
        guard w.isFinite, h.isFinite, w >= 1, h >= 1, w.rounded(.down) == w, h.rounded(.down) == h else {
            throw ImageAttachmentError.invalidImage
        }
        guard w <= Double(maximumDimension), h <= Double(maximumDimension), w * h <= Double(maximumPixels) else {
            throw ImageAttachmentError.pixelLimitExceeded
        }
        return (Int(w), Int(h))
    }

    private static func normalizedImage(_ image: CGImage) throws -> CGImage {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: image.width * 4, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw ImageAttachmentError.previewFailed
        }
        // Transparent source pixels become white rather than an accidental black background in JPEG/OCR.
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        let bounds = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
        context.fill(bounds)
        context.draw(image, in: bounds)
        guard let normalized = context.makeImage() else { throw ImageAttachmentError.previewFailed }
        return normalized
    }

    private static func previewData(_ image: CGImage) throws -> Data {
        let bytes = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ImageAttachmentError.previewFailed
        }
        // Add a newly rendered bitmap only. Never copy source GPS, EXIF, IPTC, XMP, or orientation metadata.
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination), bytes.length > 0, bytes.length <= maximumPreviewBytes else {
            throw ImageAttachmentError.previewFailed
        }
        return bytes as Data
    }

    private static func recognizeText(in image: CGImage) -> ImageOCRResult {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.automaticallyDetectsLanguage = true
        request.minimumTextHeight = 0.005
        do {
            try VNImageRequestHandler(cgImage: image, orientation: .up, options: [:]).perform([request])
            // One extra observation allows the formatter to disclose a line-limit truncation.
            let lines = (request.results ?? []).prefix(ImageOCRResult.maximumLines + 1).compactMap {
                $0.topCandidates(1).first?.string
            }
            return .bounded(lines: lines)
        } catch {
            // A valid image remains viewable/shareable when Vision is unavailable or recognition fails.
            return .unavailable
        }
    }

    private func persist(original: Data, originalName: String, preview: Data, previewName: String) throws {
        let folder = Darwin.open(directory.path, O_RDONLY | O_CLOEXEC | O_DIRECTORY | O_NOFOLLOW)
        guard folder >= 0 else { throw ImageAttachmentError.storageUnavailable }
        defer { Darwin.close(folder) }
        var created: [String] = []
        do {
            for (name, bytes) in [(originalName, original), (previewName, preview)] {
                // Exclusive, relative creation prevents overwrites and does not follow an existing symlink.
                let descriptor = Darwin.openat(folder, name, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, mode_t(0o600))
                guard descriptor >= 0 else { throw ImageAttachmentError.storageUnavailable }
                created.append(name)
                do {
                    try bytes.withUnsafeBytes { buffer in
                        var offset = 0
                        while offset < buffer.count {
                            try Task.checkCancellation()
                            let count = Darwin.write(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                            if count < 0, errno == EINTR { continue }
                            guard count > 0 else { throw ImageAttachmentError.storageUnavailable }
                            offset += count
                        }
                    }
                } catch {
                    Darwin.close(descriptor)
                    throw error
                }
                guard Darwin.close(descriptor) == 0 else { throw ImageAttachmentError.storageUnavailable }
            }
        } catch {
            // Remove only files this import successfully created, through the same opened directory.
            for name in created { Darwin.unlinkat(folder, name, 0) }
            throw error
        }
    }

    private static func displayName(_ proposed: String, fallback: String) -> String {
        let last = proposed.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init) ?? ""
        let clean = last.components(separatedBy: .controlCharacters).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty || clean == "." || clean == ".." ? fallback : String(clean.prefix(200))
    }
}

enum ImageAttachmentError: LocalizedError, Equatable {
    case invalidSize, invalidImage, unsupportedFormat, multipleFrames, pixelLimitExceeded
    case unsafeFile, unreadableFile, previewFailed, storageUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidSize: return "Choose a nonempty image up to 10 MB."
        case .invalidImage: return "This file is not a complete, readable image."
        case .unsupportedFormat: return "Choose a JPEG, PNG, HEIC, or HEIF image."
        case .multipleFrames: return "Animated or multi-image files are not supported. Choose one still image."
        case .pixelLimitExceeded: return "Choose an image up to 40 megapixels, with each side no longer than 16,384 pixels."
        case .unsafeFile: return "Choose a regular image file, not a folder or symbolic link."
        case .unreadableFile: return "This image file could not be read. Choose it again."
        case .previewFailed: return "A safe preview could not be created for this image."
        case .storageUnavailable: return "The image could not be saved in private app storage. Check available storage and try again."
        }
    }
}
