import XCTest
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
@testable import ArchiveExtraction

final class ZIPExtractorTests: XCTestCase {
    func zip(_ names: [String] = ["notes/a.txt"], deflated: Bool = false, raw: Data? = nil, wide: Bool = false, descriptor: Bool = false, expectedBytes: UInt32 = 3, checksum: UInt32 = 0x352441c2) -> Data {
        var result = Data(), central = Data()
        for name in names {
            let n = Data(name.utf8), body = raw ?? (deflated ? Data([0x4b,0x4c,0x4a,0x06,0x00]) : Data("abc".utf8))
            let offset = result.count, flags:UInt16 = descriptor ? 0x808:0x800
            var extra=Data();if wide { extra.u16(1);extra.u16(16);extra.u64(descriptor ? 0:UInt64(expectedBytes));extra.u64(descriptor ? 0:UInt64(body.count)) }
            result.u32(0x04034b50);result.u16(wide ? 45:20);result.u16(flags);result.u16(deflated ? 8:0)
            result.u16(0);result.u16(0);result.u32(descriptor ? 0:checksum)
            result.u32(wide ? 0xffffffff:(descriptor ? 0:UInt32(body.count)));result.u32(wide ? 0xffffffff:(descriptor ? 0:expectedBytes))
            result.u16(UInt16(n.count));result.u16(UInt16(extra.count));result.append(n);result.append(extra);result.append(body)
            if descriptor { result.u32(0x08074b50);result.u32(checksum);if wide { result.u64(UInt64(body.count));result.u64(UInt64(expectedBytes)) } else {result.u32(UInt32(body.count));result.u32(expectedBytes)} }
            extra=Data();if wide { extra.u16(1);extra.u16(24);extra.u64(UInt64(expectedBytes));extra.u64(UInt64(body.count));extra.u64(UInt64(offset)) }
            central.u32(0x02014b50);central.u16(0x0314);central.u16(wide ? 45:20);central.u16(flags);central.u16(deflated ? 8:0)
            central.u16(0);central.u16(0);central.u32(checksum);central.u32(wide ? 0xffffffff:UInt32(body.count));central.u32(wide ? 0xffffffff:expectedBytes)
            central.u16(UInt16(n.count));central.u16(UInt16(extra.count));central.u16(0);central.u16(0);central.u16(0);central.u32(0x81a40000);central.u32(wide ? 0xffffffff:UInt32(offset));central.append(n);central.append(extra)
        }
        let start=result.count;result.append(central)
        if wide {
            let zoffset=result.count
            result.u32(0x06064b50);result.u64(44);result.u16(45);result.u16(45);result.u32(0);result.u32(0);result.u64(UInt64(names.count));result.u64(UInt64(names.count));result.u64(UInt64(central.count));result.u64(UInt64(start))
            result.u32(0x07064b50);result.u32(0);result.u64(UInt64(zoffset));result.u32(1)
        }
        result.u32(0x06054b50);result.u16(0);result.u16(0);result.u16(wide ? 0xffff:UInt16(names.count));result.u16(wide ? 0xffff:UInt16(names.count));result.u32(wide ? 0xffffffff:UInt32(central.count));result.u32(wide ? 0xffffffff:UInt32(start));result.u16(0)
        return result
    }
    func withArchive(_ data: Data, _ body: (URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("original.zip"), destination = root.appendingPathComponent("staging")
        try data.write(to: source);try body(source,destination)
        XCTAssertEqual(try Data(contentsOf: source), data, "Original archive must not change")
    }
    func testStoredAndDeflatedFilesExtractWithVerifiedBytes() throws {
        for compressed in [false,true] { try withArchive(zip(deflated: compressed)) { source,destination in
            let entries = try ZIPExtractor.extract(source: source, destination: destination)
            XCTAssertEqual(entries.count,1);XCTAssertEqual(entries.first?.path,"notes/a.txt")
            XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("notes/a.txt")),Data("abc".utf8))
        } }
    }
    func testTraversalAndCanonicalDuplicatesRejected() throws {
        for names in [["../escape"],["/absolute"],["C:/drive"],["a\\b"],["a","A"],["a","a/b"],["a/b","a"],["é","e\u{301}"]] {
            try withArchive(zip(names)) { s,d in XCTAssertThrowsError(try ZIPExtractor.extract(source:s,destination:d)) }
        }
    }
    func testExistingDestinationIsNeverOverwritten() throws {
        try withArchive(zip()) { s,d in
            try FileManager.default.createDirectory(at:d,withIntermediateDirectories:true)
            let marker=d.appendingPathComponent("keep");try Data("old".utf8).write(to:marker)
            XCTAssertThrowsError(try ZIPExtractor.extract(source:s,destination:d));XCTAssertEqual(try String(contentsOf:marker,encoding:.utf8),"old")
        }
    }
    func testLimitsAndCancellationFailClosed() throws {
        try withArchive(zip()) { s,d in
            var limits=ZIPExtractor.Limits();limits.totalBytes=2
            XCTAssertThrowsError(try ZIPExtractor.extract(source:s,destination:d,limits:limits))
            XCTAssertThrowsError(try ZIPExtractor.extract(source:s,destination:d,cancelled:{true}))
        }
    }
    func testCRCAndTruncatedArchiveRejected() throws {
        var bad=zip();bad["notes/a.txt".utf8.count+30]=0
        for data in [bad,Data(zip().dropLast()),Data("not zip".utf8)] { try withArchive(data) { s,d in XCTAssertThrowsError(try ZIPExtractor.extract(source:s,destination:d)) } }
    }
    func testZIP64AndSignedDescriptors() throws {
        for wide in [false,true] { for descriptor in [false,true] {
            try withArchive(zip(deflated:true,wide:wide,descriptor:descriptor)) { s,d in
                XCTAssertEqual(try ZIPExtractor.extract(source:s,destination:d).first?.bytes,3)
                XCTAssertEqual(try Data(contentsOf:d.appendingPathComponent("notes/a.txt")),Data("abc".utf8))
            }
        } }
    }
    func testNonfinalTruncatedAndTrailingDeflateStreamsRejected() throws {
        for raw in [Data([0x4a,0x4c,0x4a,0x06,0x00]),Data([0x4b,0x4c,0x4a,0x06]),Data([0x4b,0x4c,0x4a,0x06,0x00,0x00]),Data([0x03,0x00])] {
            try withArchive(zip(deflated:true,raw:raw)) { s,d in XCTAssertThrowsError(try ZIPExtractor.extract(source:s,destination:d)) }
        }
    }
    func testEncryptionSpecialFilesAndMultidiskRejected() throws {
        for kind in ["encrypted","symlink","fifo","multidisk"] {
            var data=zip();let central=data.signature(0x02014b50)
            switch kind {
            case "encrypted": data[6]|=1;data[central+8]|=1
            case "symlink": data.set32(central+38,0xa1ff0000)
            case "fifo": data.set32(central+38,0x11ff0000)
            default: data[data.count-18]=1
            }
            try withArchive(data) { s,d in XCTAssertThrowsError(try ZIPExtractor.extract(source:s,destination:d)) }
        }
    }
    func testDescriptorMismatchAndMemberOverlapRejected() throws {
        var descriptor=zip(descriptor:true);descriptor[descriptor.signature(0x08074b50)+4]^=1
        var overlap=zip(["a","b"]);let second=overlap.signature(0x02014b50,after:overlap.signature(0x02014b50)+4);overlap.set32(second+42,0)
        var sizes=zip();sizes.set32(18,4);sizes.set32(sizes.signature(0x02014b50)+20,4)
        for data in [descriptor,overlap,sizes] { try withArchive(data) { s,d in XCTAssertThrowsError(try ZIPExtractor.extract(source:s,destination:d)) } }
    }
    func testFailsKeepPartialStagingAndSourceButNeverOutsideWrites() throws {
        var data=zip();data[41]=0
        try withArchive(data) { s,d in
            XCTAssertThrowsError(try ZIPExtractor.extract(source:s,destination:d))
            XCTAssertTrue(FileManager.default.fileExists(atPath:d.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath:s.path))
        }
    }

    func testFIFOInputIsRejectedWithoutWaitingForWriter() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let fifo=root.appendingPathComponent("input.fifo")
        XCTAssertEqual(mkfifo(fifo.path,0o600),0)
        XCTAssertThrowsError(try ZIPExtractor.extract(source:fifo,destination:root.appendingPathComponent("out")))
    }

    func testValidEmbeddedLocalHeadersCannotOverlap() throws {
        // Both local headers and CRCs individually valid; second range nests in first.
        let data=Data(base64Encoded:"UEsDBBQAAAgAAAAAAADv/2f5IgAAACIAAAABAAAAYVBLAwQUAAAIAAAAAAAAwkEkNQMAAAADAAAAAQAAAGJhYmNQSwECFAMUAAAIAAAAAAAA7/9n+SIAAAAiAAAAAQAAAAAAAAAAAAAApIEAAAAAYVBLAQIUAxQAAAgAAAAAAADCQSQ1AwAAAAMAAAABAAAAAAAAAAAAAACkgR8AAABiUEsFBgAAAAACAAIAXgAAAEEAAAAAAA==")!
        try withArchive(data) { source,destination in
            XCTAssertThrowsError(try ZIPExtractor.extract(source:source,destination:destination))
            XCTAssertFalse(FileManager.default.fileExists(atPath:destination.path))
        }
    }
    func testActualInflatedBytesCannotExceedAdvertisedLimit() throws {
        let raw=Data(base64Encoded:"7cExAQAAAMKgbOtfyhoeQAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACvBg==")! // 100,000 synthetic A bytes, header advertises 3.
        try withArchive(zip(deflated:true,raw:raw)) { source,destination in
            XCTAssertThrowsError(try ZIPExtractor.extract(source:source,destination:destination))
            let path=destination.appendingPathComponent("notes/a.txt")
            let bytes=(try FileManager.default.attributesOfItem(atPath:path.path)[.size] as! NSNumber).intValue
            XCTAssertLessThanOrEqual(bytes,3)
        }
    }
    func testRejectsSymlinkSourceAndDestination() throws {
        try withArchive(zip()) { source,destination in
            let link=source.deletingLastPathComponent().appendingPathComponent("link.zip")
            try FileManager.default.createSymbolicLink(at:link,withDestinationURL:source)
            XCTAssertThrowsError(try ZIPExtractor.extract(source:link,destination:destination))
            try FileManager.default.createSymbolicLink(at:destination,withDestinationURL:source.deletingLastPathComponent())
            XCTAssertThrowsError(try ZIPExtractor.extract(source:source,destination:destination))
        }
    }
    func testCancellationAfterStagingRetainsRecoverablePartialFiles() throws {
        try withArchive(zip()) { source,destination in
            var checks=0
            XCTAssertThrowsError(try ZIPExtractor.extract(source:source,destination:destination,cancelled:{ checks+=1;return checks>=5 }))
            XCTAssertTrue(FileManager.default.fileExists(atPath:destination.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath:source.path))
        }
    }

    func testDeflateDrainsMultipleOutputChunksAfterInputConsumed() throws {
        let raw=Data(base64Encoded:"7cExAQAAAMKgbOtfyhoeQAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACvBg==")!
        try withArchive(zip(deflated:true,raw:raw,expectedBytes:100000,checksum:92970967)) { source,destination in
            XCTAssertEqual(try ZIPExtractor.extract(source:source,destination:destination).first?.bytes,100000)
            XCTAssertEqual(try Data(contentsOf:destination.appendingPathComponent("notes/a.txt")),Data(repeating:65,count:100000))
        }
    }

    func testInsufficientCapacityDoesNotCreateDestination() throws {
        try withArchive(zip()) { source,destination in
            var limits=ZIPExtractor.Limits();limits.reserveBytes=UInt64.max
            XCTAssertThrowsError(try ZIPExtractor.extract(source:source,destination:destination,limits:limits))
            XCTAssertFalse(FileManager.default.fileExists(atPath:destination.path))
        }
    }

}
private extension Data {
    func signature(_ value:UInt32,after:Int=0)->Int { var sig=Data();sig.u32(value);return range(of:sig,in:after..<count)!.lowerBound }
    mutating func set32(_ at:Int,_ v:UInt32) { var d=Data();d.u32(v);replaceSubrange(at..<at+4,with:d) }
    mutating func u64(_ v:UInt64) { u32(UInt32(v & 0xffffffff));u32(UInt32(v >> 32)) }
    mutating func u16(_ v: UInt16) { append(UInt8(v & 255));append(UInt8(v >> 8)) }
    mutating func u32(_ v: UInt32) { u16(UInt16(v & 65535));u16(UInt16(v >> 16)) }
}
