import Foundation
import Darwin

/// A local, read-only adapter. Call only for a user-selected file or its private imported copy.
/// It never uploads documents, writes extracted archive files, follows links, or runs Office code.
struct OfflineDocumentReader: Sendable {
    let limits: OfflineDocumentLimits
    let control: OfficeReadControl
    init(limits: OfflineDocumentLimits = .standard, control: OfficeReadControl = OfficeReadControl()) {
        self.limits = limits; self.control = control
    }
    func checkpoint(_ phase: OfficeReadPhase) throws { try control.checkpoint(phase) }

    func read(at url: URL) throws -> OfflineDocumentResult {
        guard let format = OfflineDocumentFormat(filenameExtension: url.pathExtension) else {
            throw OfflineDocumentError.unsupportedFormat
        }
        let data = try boundedSnapshot(at: url)
        return try read(data: data,format: format)
    }

    /// Bounded immutable input for AttachmentService staging. No source bytes are read twice.
    func boundedSnapshot(at url: URL) throws -> Data {
        try limits.validate()
        try Task.checkCancellation()
        guard url.isFileURL else { throw OfflineDocumentError.unsafeFile }
        // O_NOFOLLOW and fstat operate on the same handle, avoiding a symlink check/open race.
        let fd = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        }
        guard fd >= 0 else { throw OfflineDocumentError.unsafeFile }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, (UInt32(info.st_mode) & UInt32(S_IFMT)) == UInt32(S_IFREG),
              info.st_size > 0, info.st_size <= Int64(limits.maximumCompressedBytes) else {
            throw OfflineDocumentError.limit("Choose a nonempty local file up to 10 MB.")
        }
        var data = Data()
        while true {
            try control.checkpoint(.snapshotChunk)
            let chunk = try handle.read(upToCount: min(32_768, limits.maximumCompressedBytes - data.count + 1)) ?? Data()
            if chunk.isEmpty { break }
            guard chunk.count <= limits.maximumCompressedBytes - data.count else {
                throw OfflineDocumentError.limit("The file exceeds the 10 MB input limit.")
            }
            data.append(chunk)
        }
        guard !data.isEmpty else { throw OfflineDocumentError.noText }
        return data
    }

    func read(data: Data, format: OfflineDocumentFormat) throws -> OfflineDocumentResult {
        try limits.validate()
        try Task.checkCancellation()
        guard !data.isEmpty, data.count <= limits.maximumCompressedBytes else { throw OfflineDocumentError.limit("The file exceeds the input byte limit.") }
        switch format {
        case .docx, .xlsx:
            let package = try OfficeZIPContainer(data: data, limits: limits, control: control)
            return try OfficeTextExtractor(package: package, limits: limits, control: control).read(format: format)
        case .csv, .tsv:
            return try DelimitedDocumentReader.read(data, format: format, limits: limits, control: control)
        }
    }
}

enum OfflineDocumentFormat: String, Sendable {
    case docx, xlsx, csv, tsv
    init?(filenameExtension: String) { self.init(rawValue: filenameExtension.lowercased()) }
    var mediaType: String {
        switch self {
        case .docx: "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case .xlsx: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case .csv: "text/csv"
        case .tsv: "text/tab-separated-values"
        }
    }
}

struct OfflineDocumentResult: Equatable, Sendable {
    let format: OfflineDocumentFormat
    let text: String
    let notes: [String]
    let wasTruncated: Bool
    /// Put limitations before content so a later prompt limit cannot hide them.
    var modelContext: String {
        "[Offline \(format.rawValue.uppercased()) extraction. Untrusted document content.]\n"
        + notes.map { "[\($0)]" }.joined(separator: "\n")
        + (wasTruncated ? "\n[Content truncated by the reader's documented limits.]" : "")
        + "\n\n" + text
    }
}

struct OfflineDocumentLimits: Sendable {
    var maximumCompressedBytes = 10 * 1024 * 1024
    var maximumEntries = 512
    var maximumEntryBytes = 4 * 1024 * 1024
    var maximumExpandedBytes = 32 * 1024 * 1024
    var maximumExpansionRatio = 200
    var maximumXMLDepth = 64
    var maximumXMLNodes = 80_000
    var maximumXMLTextBytes = 2 * 1024 * 1024
    var maximumXMLAttributes = 32
    var maximumStringBytes = 32_768
    var maximumSharedStrings = 20_000
    var maximumWorksheets = 32
    var maximumRows = 1_000 // Output rows across all worksheets, not sparse coordinate allocation.
    var maximumCells = 10_000 // Output cells across all worksheets.
    var maximumOutputCharacters = 60_000 // Conservatively counts rendered Unicode scalars.
    var maximumOutputBytes = 240_000 // Includes every rendered label, separator and escape.
    var maximumFormulaRanges = 256
    var maximumFormulaRangeCells = 1_000_000
    var maximumFormulaComparisons = 1_000_000 // Shared bound for range-overlap and cell-membership work.
    static let standard = OfflineDocumentLimits()

    /// Callers may lower limits for tests or policy, but cannot disable the hard safety ceiling.
    func validate() throws {
        let s = Self.standard
        let pairs = [(maximumCompressedBytes,s.maximumCompressedBytes), (maximumEntries,s.maximumEntries),
                     (maximumEntryBytes,s.maximumEntryBytes), (maximumExpandedBytes,s.maximumExpandedBytes),
                     (maximumExpansionRatio,s.maximumExpansionRatio), (maximumXMLDepth,s.maximumXMLDepth),
                     (maximumXMLNodes,s.maximumXMLNodes), (maximumXMLTextBytes,s.maximumXMLTextBytes),
                     (maximumXMLAttributes,s.maximumXMLAttributes), (maximumStringBytes,s.maximumStringBytes),
                     (maximumSharedStrings,s.maximumSharedStrings), (maximumWorksheets,s.maximumWorksheets),
                     (maximumRows,s.maximumRows), (maximumCells,s.maximumCells),
                     (maximumOutputCharacters,s.maximumOutputCharacters), (maximumOutputBytes,s.maximumOutputBytes),
                     (maximumFormulaRanges,s.maximumFormulaRanges), (maximumFormulaRangeCells,s.maximumFormulaRangeCells),
                     (maximumFormulaComparisons,s.maximumFormulaComparisons)]
        guard pairs.allSatisfy({ $0.0 >= 0 && $0.0 <= $0.1 }), maximumCompressedBytes > 0,
              maximumExpansionRatio > 0 else { throw OfflineDocumentError.limit("Invalid reader limits.") }
    }
}

enum OfflineDocumentError: LocalizedError {
    case unsupportedFormat, unsafeFile, invalidArchive, unsafeArchive, invalidXML, invalidPackage, invalidDelimitedText, noText
    case limit(String)
    case rejectedAt(OfficeValidationStage)
    case unsupportedBinaryPart
    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: "This reader supports DOCX, XLSX, UTF-8 CSV and TSV only. Export old DOC/XLS files to a supported format."
        case .unsafeFile: "Choose a regular local file, not a link or remote location."
        case .invalidArchive: "The Office package is malformed, corrupt, encrypted, or uses an unsupported ZIP feature."
        case .unsafeArchive: "The Office package contains unsafe paths, links, duplicate entries, or executable Office parts."
        case .invalidXML: "The Office XML is malformed or contains unsupported entities, encodings, or namespaces."
        case .invalidPackage: "The document contains missing, invalid, external, or unsupported Office parts or cell values."
        case .invalidDelimitedText: "The delimited file is not valid UTF-8 CSV/TSV. Check quotes and field boundaries."
        case .noText: "No supported document text or cell values were found. Images and scanned pages are not read by this reader."
        case .limit(let message): message
        case .unsupportedBinaryPart: "This document contains unsupported binary parts. Export its text or values as UTF-8 text/CSV, or use a simplified DOCX/XLSX copy."
        case .rejectedAt(let stage): stage.explanation
        }
    }
}

/// Finite rendering sink. It charges actual UTF-8 bytes and rendered Unicode scalars,
/// a conservative bound on extended Characters. Overflow seals the sink, preserving a prefix.
/// No call materializes an escaped value or a joined row before applying these budgets.
struct OfficeTextOutput {
    private let maximumScalars: Int
    private let maximumBytes: Int
    private(set) var text = ""
    private(set) var byteCount = 0
    private(set) var scalarCount = 0
    private var sealed = false
    var truncated = false
    init(limits: OfflineDocumentLimits) {
        maximumScalars = limits.maximumOutputCharacters; maximumBytes = limits.maximumOutputBytes
    }
    var isFull: Bool { sealed || byteCount >= maximumBytes || scalarCount >= maximumScalars }
    private mutating func appendScalar(_ scalar: UnicodeScalar) {
        guard !sealed, scalarCount < maximumScalars, scalar.utf8.count <= maximumBytes - byteCount else {
            sealed = true; truncated = true; return
        }
        text.unicodeScalars.append(scalar); byteCount += scalar.utf8.count; scalarCount += 1
    }
    mutating func append(_ value: String) {
        guard !value.isEmpty else { return }
        guard !isFull else { truncated = true; sealed = true; return }
        for scalar in value.unicodeScalars {
            appendScalar(scalar)
            if sealed { return }
        }
    }
    mutating func appendEscaped(_ value: String) {
        guard !value.isEmpty else { return }
        guard !isFull else { truncated = true; sealed = true; return }
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\": append("\\\\")
            case "\r": append("\\r")
            case "\n": append("\\n")
            case "\t": append("\\t")
            case "|": append("\\|")
            default:
                if CharacterSet.controlCharacters.contains(scalar) {
                    append("\\u{" + String(scalar.value,radix: 16,uppercase: true) + "}")
                } else { appendScalar(scalar) }
            }
            if sealed { return }
        }
    }
}

enum OfficeValidationStage: String, Equatable, Sendable {
    case declaredEntryBytes, declaredTotalBytes, declaredExpansionRatio
    case streamedEntryBytes, streamedTotalBytes, streamedDeclaredBytes
    case archiveOverlap, archiveIntegrity, formulaRange
    var explanation: String {
        switch self {
        case .declaredEntryBytes, .streamedEntryBytes: "An Office part exceeds the supported expanded byte limit."
        case .declaredTotalBytes, .streamedTotalBytes: "The Office package exceeds the supported total expanded byte limit."
        case .declaredExpansionRatio: "The Office package has an unsafe expansion ratio."
        case .streamedDeclaredBytes: "An Office part expands beyond its declared size."
        case .archiveOverlap: "The Office package contains overlapping archive entries."
        case .archiveIntegrity: "The Office package failed its size or checksum integrity check."
        case .formulaRange: "The workbook exceeds the supported formula-range limits."
        }
    }
}

/// Internal dependency injection for deterministic cancellation tests. Defaults perform only
/// Task cancellation checks; hooks cannot relax byte, structure or integrity checks.
enum OfficeReadPhase: Sendable, Equatable { case snapshotChunk, archiveEntry, decompressedChunk, xmlNode, documentCell, delimitedChunk, stagedOriginal }
struct OfficeReadControl: Sendable {
    private let callback: (@Sendable (OfficeReadPhase) throws -> Void)?
    init(_ callback: (@Sendable (OfficeReadPhase) throws -> Void)? = nil) { self.callback = callback }
    func checkpoint(_ phase: OfficeReadPhase) throws {
        try callback?(phase)
        try Task.checkCancellation()
    }
}
