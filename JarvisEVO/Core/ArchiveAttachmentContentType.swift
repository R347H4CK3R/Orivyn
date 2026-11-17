import Foundation

/// Selects an existing decoder for one explicitly selected, verified .dat file.
/// This is NOT format validity or a file-to-message association.
enum ArchiveAttachmentContentType {
    enum Failure: LocalizedError {
        case unsupported
        var errorDescription: String? { "This selected .dat file is not recognizable as a supported image, PDF, or plain UTF-8 text. The original archive is unchanged." }
    }
    static func classify(_ data: Data) throws -> String {
        try Task.checkCancellation()
        guard !data.isEmpty, data.count <= 10 * 1024 * 1024 else { throw Failure.unsupported }
        if data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) { return "png" }
        if data.starts(with: [255, 216, 255]) { return "jpg" }
        if data.starts(with: Array("%PDF-".utf8)) { return "pdf" }
        // ISO BMFF: inspect just a bounded, complete first ftyp box. Generic
        // mif1/isom brands alone do not establish a supported still image.
        if data.count >= 16, data.dropFirst(4).starts(with: Array("ftyp".utf8)) {
            let prefix = Array(data.prefix(512))
            let size = prefix.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
            guard size >= 16, size <= 512, size <= data.count, (size - 16) % 4 == 0 else { throw Failure.unsupported }
            let still = Set(["heic", "heix", "heim", "heis"])
            let positions = [8] + Array(stride(from: 16, to: size, by: 4))
            if positions.contains(where: { still.contains(String(decoding: prefix[$0..<($0 + 4)], as: UTF8.self)) }) { return "heic" }
            throw Failure.unsupported
        }
        guard let text = String(data: data, encoding: .utf8) else { throw Failure.unsupported }
        var meaningful = false
        for (index, scalar) in text.unicodeScalars.enumerated() {
            if index % 4096 == 0 { try Task.checkCancellation() }
            let value = scalar.value
            guard !(value < 32 && value != 9 && value != 10 && value != 13),
                  !(127...159).contains(value) else { throw Failure.unsupported }
            if !CharacterSet.whitespacesAndNewlines.contains(scalar) { meaningful = true }
        }
        guard meaningful else { throw Failure.unsupported }
        try Task.checkCancellation()
        return "txt"
    }
}
