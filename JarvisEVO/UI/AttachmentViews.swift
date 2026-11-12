import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import QuickLook
import AVFoundation

/// Read the temporary Photos file during the provider callback, while its grant
/// is valid. Only bounded copied bytes cross into the asynchronous import task.
struct PickedImage: Sendable {
    let data: Data
    let name: String
    @MainActor static func load(from provider: NSItemProvider) async throws -> PickedImage {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, error in
                if let error { continuation.resume(throwing: error); return }
                guard let url else { continuation.resume(throwing: AttachmentError.unsupportedType); return }
                do { continuation.resume(returning: try read(url)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
    private static func read(_ url: URL) throws -> PickedImage {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= AttachmentService.maximumBytes else {
            throw AttachmentError.invalidSize
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard !data.isEmpty, data.count <= AttachmentService.maximumBytes else { throw AttachmentError.invalidSize }
        return PickedImage(data: data, name: url.lastPathComponent)
    }
}

/// Each presentation has an immutable completion closure. A late delegate result
/// therefore retains its original conversation/import context, never a new one.
struct PhotoAttachmentPicker: UIViewControllerRepresentable {
    let selectionLimit: Int
    let complete: ([NSItemProvider]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(complete: complete) }
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = selectionLimit
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: PHPickerViewController, context: Context) { }
    @MainActor final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let complete: ([NSItemProvider]) -> Void
        init(complete: @escaping ([NSItemProvider]) -> Void) { self.complete = complete }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            complete(results.map(\.itemProvider))
        }
    }
}

struct FileAttachmentPicker: UIViewControllerRepresentable {
    let complete: (Result<[URL], any Error>) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(complete: complete) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf, .plainText, .json, .sourceCode, .jpeg, .png, .heic, .heif], asCopy: false)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) { }
    @MainActor final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let complete: (Result<[URL], any Error>) -> Void
        init(complete: @escaping (Result<[URL], any Error>) -> Void) { self.complete = complete }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { complete(.success(urls)) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { complete(.success([])) }
    }
}

struct AttachmentTile: View {
    let attachment: ChatAttachment
    let previewURL: URL?
    let open: () -> Void
    var remove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Button(action: open) {
                HStack(spacing: 8) {
                    if attachment.isImage, let previewURL, let image = UIImage(contentsOfFile: previewURL.path) {
                        Image(uiImage: image).resizable().scaledToFill().frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Image(systemName: attachment.isImage ? "photo" : "doc.text").frame(width: 28, height: 36)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(attachment.name).lineLimit(2)
                        if attachment.isImage { Text("Recognized text only").foregroundStyle(.secondary) }
                    }.font(.caption).frame(maxWidth: 165, alignment: .leading)
                }.contentShape(Rectangle())
            }
            .accessibilityLabel("Preview \(attachment.name)")
            .accessibilityIdentifier("attachment.preview.\(attachment.id)")
            if let remove {
                Button(action: remove) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).frame(width: 32, height: 44) }
                    .accessibilityLabel("Remove \(attachment.name)").accessibilityIdentifier("attachment.remove.\(attachment.id)")
            }
        }
        .padding(8).background(Color.evoSurface, in: RoundedRectangle(cornerRadius: 14)).buttonStyle(.plain)
    }
}

struct AttachmentPreviewView: View {
    let attachment: ChatAttachment
    let originalURL: URL?
    let previewURL: URL?
    @Environment(\.dismiss) private var dismiss
    @State private var warnOriginal = false
    @State private var shareOriginal = false

    var body: some View {
        NavigationStack {
            Group {
                if attachment.isImage {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if let previewURL, let image = UIImage(contentsOfFile: previewURL.path) {
                                Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity)
                                    .accessibilityLabel("Image preview").accessibilityIdentifier("attachment.image")
                            } else { Label("Preview is unavailable", systemImage: "photo").foregroundStyle(.secondary) }
                            Text("Images are read with on-device text recognition. Current models receive recognized text, not image pixels. They cannot describe objects or generate images.")
                                .font(.callout).accessibilityIdentifier("attachment.ocr.notice")
                            Text("Recognized text").font(.headline)
                            Text(attachment.extractedText ?? "No text was recognized.").textSelection(.enabled)
                                .accessibilityIdentifier("attachment.ocr.text")
                            if let previewURL {
                                ShareLink(item: previewURL) { Label("Share clean preview", systemImage: "square.and.arrow.up") }
                                    .accessibilityIdentifier("attachment.share.clean")
                                Text("The preview has photo metadata removed and is resized to at most 2048 pixels.").font(.caption).foregroundStyle(.secondary)
                            }
                            if originalURL != nil {
                                Button("Share original file…") { warnOriginal = true }
                                    .accessibilityIdentifier("attachment.share.original")
                            }
                        }.padding()
                    }
                } else if let originalURL {
                    DocumentPreview(url: originalURL)
                } else {
                    ScrollView { Text(attachment.extractedText ?? "This file is no longer on this iPhone.").textSelection(.enabled).padding() }
                }
            }
            .navigationTitle(attachment.name).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("attachment.preview.done") } }
            .confirmationDialog("Share original photo?", isPresented: $warnOriginal, titleVisibility: .visible) {
                Button("Share original") { shareOriginal = true }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("The original file may contain location (GPS), capture time, device details, and other photo metadata. The clean preview removes this metadata. Share the original only with people or apps you trust.")
            }
            .sheet(isPresented: $shareOriginal) {
                if let originalURL { SystemShareSheet(items: [originalURL]) }
            }
        }
    }
}

private struct DocumentPreview: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: QLPreviewController, context: Context) { }
    @MainActor final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem { url as NSURL }
    }
}

private struct SystemShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}

struct CameraAttachmentPicker: UIViewControllerRepresentable {
    let complete: (Result<Data?, any Error>) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(complete: complete) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier]
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) { }
    @MainActor final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let complete: (Result<Data?, any Error>) -> Void
        init(complete: @escaping (Result<Data?, any Error>) -> Void) { self.complete = complete }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { complete(.success(nil)) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.9),
                  data.count <= AttachmentService.maximumBytes else { complete(.failure(AttachmentError.invalidSize)); return }
            complete(.success(data))
        }
    }
}

struct AttachmentPickerRequest: Identifiable {
    enum Kind { case files, photos, camera }
    let id = UUID()
    let context: UUID
    let kind: Kind
    let limit: Int
}

/// Delegate callbacks keep their immutable request. Cancel/reopen within the
/// same conversation still requires a new presentation identity, not just epoch.
struct AttachmentPickerOwnership {
    private(set) var activeID: UUID?
    mutating func open(_ request: AttachmentPickerRequest) { activeID = request.id }
    mutating func cancel(id: UUID) { if activeID == id { activeID = nil } }
    mutating func consume(_ request: AttachmentPickerRequest, currentContext: UUID) -> Bool {
        guard activeID == request.id else { return false }
        activeID = nil
        return request.context == currentContext
    }
}
