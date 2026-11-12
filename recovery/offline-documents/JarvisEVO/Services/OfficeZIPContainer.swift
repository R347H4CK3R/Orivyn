import Foundation
import ZIPFoundation

/// Metadata validation only. Decompression and CRC are performed by pinned ZIPFoundation.
/// Strict ZIP32 profile deliberately rejects ZIP64, multi-disk, encryption, extra executable parts,
/// ambiguous names, inconsistent headers, overlapping data and unsupported compression methods.
struct OfficeZIPContainer {
    let parts: [String: Data]
    let names: Set<String>

    init(data: Data, limits: OfflineDocumentLimits, control: OfficeReadControl = OfficeReadControl()) throws {
        let metadata = try OfficeZIPPreflight.read(data, limits: limits)
        let archive: Archive
        do { archive = try Archive(data: data, accessMode: .read) }
        catch { throw OfflineDocumentError.invalidArchive }
        var entries = [Entry]()
        for entry in archive {
            try control.checkpoint(.archiveEntry)
            guard entries.count < limits.maximumEntries else { throw OfflineDocumentError.invalidArchive }
            entries.append(entry)
        }
        guard entries.count == metadata.count else { throw OfflineDocumentError.invalidArchive }
        var saved = [String: Data](), seen = Set<String>(), total = 0
        for entry in entries {
            guard let m = metadata[entry.path], seen.insert(entry.path).inserted,
                  entry.type != .symlink, entry.type == (m.isDirectory ? .directory : .file),
                  entry.compressedSize == UInt64(m.compressed), entry.uncompressedSize == UInt64(m.expanded),
                  entry.checksum == m.crc else { throw OfflineDocumentError.invalidArchive }
            let keep = entry.path.hasSuffix(".xml") || entry.path.hasSuffix(".rels")
            var content = Data(), actual = 0, calls = 0, emptyCalls = 0
            // The callback limits REAL bytes, even if an attacker lies in ZIP metadata.
            let crc = try archive.extract(entry, bufferSize: 16_384, skipCRC32: false) { chunk in
                try control.checkpoint(.decompressedChunk)
                calls += 1
                emptyCalls = chunk.isEmpty ? emptyCalls + 1 : 0
                guard emptyCalls <= 8, calls <= (limits.maximumEntryBytes / 16_384) + 1_024 else { throw OfflineDocumentError.invalidArchive }
                guard chunk.count <= limits.maximumEntryBytes - actual else { throw OfflineDocumentError.rejectedAt(.streamedEntryBytes) }
                guard chunk.count <= limits.maximumExpandedBytes - total else { throw OfflineDocumentError.rejectedAt(.streamedTotalBytes) }
                guard chunk.count <= m.expanded - actual else { throw OfflineDocumentError.rejectedAt(.streamedDeclaredBytes) }
                actual += chunk.count; total += chunk.count
                guard actual <= max(1, m.compressed) * limits.maximumExpansionRatio else {
                    throw OfflineDocumentError.rejectedAt(.declaredExpansionRatio)
                }
                if keep { content.append(chunk) }
            }
            guard actual == m.expanded, crc == m.crc else { throw OfflineDocumentError.rejectedAt(.archiveIntegrity) }
            if keep && !m.isDirectory { saved[entry.path] = content }
        }
        parts = saved
        names = Set(metadata.keys.filter { metadata[$0]?.isDirectory == false })
    }
}

struct OfficeZIPMetadata {
    let compressed: Int
    let expanded: Int
    let crc: UInt32
    let isDirectory: Bool
}

private enum OfficeZIPPreflight {
    static func read(_ data: Data, limits: OfflineDocumentLimits) throws -> [String: OfficeZIPMetadata] {
        guard data.count >= 22, data.count <= limits.maximumCompressedBytes else { throw OfflineDocumentError.invalidArchive }
        let b = [UInt8](data)
        func u16(_ p: Int) throws -> Int {
            guard p >= 0, p <= b.count - 2 else { throw OfflineDocumentError.invalidArchive }
            return Int(b[p]) | Int(b[p+1]) << 8
        }
        func u32(_ p: Int) throws -> Int {
            guard p >= 0, p <= b.count - 4 else { throw OfflineDocumentError.invalidArchive }
            return Int(b[p]) | Int(b[p+1]) << 8 | Int(b[p+2]) << 16 | Int(b[p+3]) << 24
        }
        func checkExtra(_ start: Int, _ length: Int) throws {
            guard start >= 0, length >= 0, start <= b.count - length else { throw OfflineDocumentError.invalidArchive }
            var p = start
            while p < start + length {
                let tag = try u16(p), size = try u16(p+2)
                guard size <= start + length - p - 4,
                      tag != 0x0001, tag != 0x9901, tag != 0x7075 else { throw OfflineDocumentError.invalidArchive }
                p += 4 + size
            }
            guard p == start + length else { throw OfflineDocumentError.invalidArchive }
        }
        var end: Int?
        for p in stride(from: b.count - 22, through: max(0, b.count - 65_557), by: -1) {
            if try u32(p) == 0x06054b50, p + 22 + (try u16(p+20)) == b.count { end = p; break }
        }
        guard let end else { throw OfflineDocumentError.invalidArchive }
        let entries = try u16(end+10), centralSize = try u32(end+12), centralStart = try u32(end+16)
        guard try u16(end+4) == 0, try u16(end+6) == 0, try u16(end+8) == entries,
              entries > 0, entries < 0xffff, entries <= limits.maximumEntries,
              centralStart < 0xffffffff, centralSize < 0xffffffff,
              centralStart + centralSize == end else { throw OfflineDocumentError.invalidArchive }
        var p = centralStart, result = [String: OfficeZIPMetadata](), folded = Set<String>()
        var ranges = [Range<Int>](), expandedTotal = 0
        for _ in 0..<entries {
            try Task.checkCancellation()
            guard p <= end - 46, try u32(p) == 0x02014b50 else { throw OfflineDocumentError.invalidArchive }
            let made = try u16(p+4), version = try u16(p+6), flags = try u16(p+8), method = try u16(p+10)
            let crc = try u32(p+16), compressed = try u32(p+20), expanded = try u32(p+24)
            let n = try u16(p+28), e = try u16(p+30), c = try u16(p+32), disk = try u16(p+34)
            let attributes = try u32(p+38), local = try u32(p+42)
            guard version <= 20, flags & ~(method == 8 ? 0x080e : 0x0808) == 0, [0,8].contains(method), disk == 0,
                  compressed < 0xffffffff, expanded < 0xffffffff, local < 0xffffffff,
                  n > 0, n <= 255, p + 46 + n + e + c <= end else { throw OfflineDocumentError.invalidArchive }
            let rawName = Array(b[(p+46)..<(p+46+n)])
            guard rawName.allSatisfy({ $0 >= 32 && $0 < 127 }), let name = String(bytes: rawName, encoding: .utf8),
                  isSafePath(name), folded.insert(name.lowercased()).inserted else { throw OfflineDocumentError.unsafeArchive }
            let directory = name.hasSuffix("/")
            let mode = (attributes >> 16) & 0xf000
            let os = made >> 8
            guard ![3,19].contains(os) || mode == 0 || mode == (directory ? 0x4000 : 0x8000),
                  attributes & 0x10 == 0 || directory else { throw OfflineDocumentError.unsafeArchive }
            let lower = name.lowercased()
            guard !lower.contains("/embeddings/"), !lower.contains("/activex/"),
                  !lower.contains("vbaproject"), !lower.contains("macrosheets/") else { throw OfflineDocumentError.unsafeArchive }
            let inertPrinter = lower.range(of: #"^(word|xl)/printersettings/printersettings[0-9]+\.bin$"#,options: .regularExpression) != nil
            guard !lower.hasSuffix(".bin") || inertPrinter else { throw OfflineDocumentError.unsupportedBinaryPart }
            guard expanded <= limits.maximumEntryBytes else { throw OfflineDocumentError.rejectedAt(.declaredEntryBytes) }
            guard expanded <= limits.maximumExpandedBytes - expandedTotal else { throw OfflineDocumentError.rejectedAt(.declaredTotalBytes) }
            guard expanded <= max(1,compressed) * limits.maximumExpansionRatio else { throw OfflineDocumentError.rejectedAt(.declaredExpansionRatio) }
            guard compressed <= data.count, (method != 0 || compressed == expanded),
                  (method != 8 || compressed > 0), (!directory || (compressed == 0 && expanded == 0 && method == 0 && crc == 0)) else { throw OfflineDocumentError.invalidArchive }
            expandedTotal += expanded
            try checkExtra(p+46+n,e)
            guard local <= centralStart - 30, try u32(local) == 0x04034b50,
                  try u16(local+4) == version, try u16(local+6) == flags, try u16(local+8) == method,
                  try u16(local+26) == n else { throw OfflineDocumentError.invalidArchive }
            let le = try u16(local+28), start = local + 30 + n + le
            guard start <= centralStart - compressed,
                  Array(b[(local+30)..<(local+30+n)]) == rawName else { throw OfflineDocumentError.invalidArchive }
            try checkExtra(local+30+n,le)
            var finish = start + compressed
            if flags & 8 == 0 {
                guard try u32(local+14) == crc, try u32(local+18) == compressed, try u32(local+22) == expanded else { throw OfflineDocumentError.invalidArchive }
            } else {
                guard [0,crc].contains(try u32(local+14)), [0,compressed].contains(try u32(local+18)), [0,expanded].contains(try u32(local+22)) else { throw OfflineDocumentError.invalidArchive }
                // Accept only the unambiguous signed descriptor profile; no ZIP64 descriptors.
                guard finish <= centralStart - 16, try u32(finish) == 0x08074b50,
                      try u32(finish+4) == crc, try u32(finish+8) == compressed, try u32(finish+12) == expanded else { throw OfflineDocumentError.invalidArchive }
                finish += 16
            }
            ranges.append(local..<finish)
            result[name] = OfficeZIPMetadata(compressed: compressed, expanded: expanded, crc: UInt32(crc), isDirectory: directory)
            p += 46+n+e+c
        }
        guard p == end else { throw OfflineDocumentError.invalidArchive }
        var cursor = 0
        for r in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            guard r.lowerBound >= cursor else { throw OfflineDocumentError.rejectedAt(.archiveOverlap) }
            guard r.lowerBound == cursor, r.upperBound > cursor else { throw OfflineDocumentError.invalidArchive }
            cursor = r.upperBound
        }
        guard cursor == centralStart else { throw OfflineDocumentError.invalidArchive }
        return result
    }

    static func isSafePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":"),
              !path.contains("%"), !path.contains("?"), !path.contains("#") else { return false }
        var components = path.split(separator: "/", omittingEmptySubsequences: false)
        if path.hasSuffix("/") { components.removeLast() }
        return components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
}
