import Foundation
import CArchive
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Extracts only into a new child of a trusted, app-private directory. Keeps
/// original bytes and failed staging untouched. Caller owns SHA-256 publication,
/// durable recovery, storage admission, and original retention.
public enum ZIPExtractor {
    public struct Limits: Sendable {
        public var entries = 20_000
        public var totalBytes: UInt64 = 20_000_000_000
        public var memberBytes: UInt64 = 4_000_000_000
        public var centralDirectoryBytes: UInt64 = 64_000_000
        public var reserveBytes: UInt64 = 64_000_000
        public init() {}
    }
    public struct Entry: Sendable { public let path: String; public let bytes: UInt64; public let crc32: UInt32 }
    public enum Failure: Error { case invalidArchive, unsafePath, unsupported, limit, cancelled, insufficientSpace; case io(operation: String, code: Int32) }
    private struct Member {
        let path: String; let directory: Bool; let method: UInt16; let flags: UInt16
        let compressed: UInt64; let expanded: UInt64; let crc: UInt32
        let offset: UInt64; let zip64Sizes: Bool
        var dataOffset: UInt64 = 0; var end: UInt64 = 0
    }
    private final class Cancellation {
        let check: () -> Bool
        init(_ check: @escaping () -> Bool) { self.check=check }
    }
    public static func extract(source: URL, destination: URL, limits: Limits = .init(), cancelled: @escaping () -> Bool = { false }) throws -> [Entry] {
        func check() throws { if cancelled() || Task.isCancelled { throw Failure.cancelled } }
        try check()
        guard source.isFileURL, destination.isFileURL, !source.path.contains("\0"), !destination.path.contains("\0"), limits.entries>0 else { throw Failure.unsafePath }
        let sourceFD=open(source.path,O_RDONLY|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK)
        guard sourceFD>=0 else { throw Failure.io(operation:"open source",code:errno) };defer { close(sourceFD) }
        var original=stat();guard fstat(sourceFD,&original)==0, (original.st_mode & S_IFMT)==S_IFREG, original.st_size>=22 else { throw Failure.invalidArchive }
        let file=Reader(fd:sourceFD,size:UInt64(original.st_size))
        let directory=try centralDirectory(file,limits:limits)
        var members=try parseMembers(file,central:directory.offset,length:directory.size,count:directory.count,limits:limits)
        var paths=Set<String>(), files=Set<String>(), directories=Set<String>()
        for index in members.indices {
            try check()
            let member=members[index], normalized=try normalizedPath(member.path,directory:member.directory)
            guard paths.insert(normalized).inserted else { throw Failure.unsafePath }
            let components=normalized.split(separator:"/").map(String.init)
            if components.count>1 {
                for end in 1..<components.count {
                    let ancestor=components.prefix(end).joined(separator:"/")
                    guard !files.contains(ancestor) else { throw Failure.unsafePath }
                    directories.insert(ancestor)
                }
            }
            if member.directory { guard !files.contains(normalized) else { throw Failure.unsafePath };directories.insert(normalized) }
            else { guard !directories.contains(normalized) else { throw Failure.unsafePath };files.insert(normalized) }
            members[index]=try validateLocal(file,member:member,centralOffset:directory.offset)
        }
        var previousEnd: UInt64=0
        for member in members.sorted(by:{$0.offset<$1.offset}) {
            guard member.offset>=previousEnd else { throw Failure.invalidArchive };previousEnd=member.end
        }
        try check()
        let expandedBytes=members.reduce(UInt64(0)) { $0+$1.expanded }
        var available:UInt64=0
        guard oz_available_space(destination.deletingLastPathComponent().path,&available)==0 else { throw Failure.io(operation:"check free space",code:errno) }
        guard limits.reserveBytes<=available,expandedBytes<=available-limits.reserveBytes else { throw Failure.insufficientSpace }
        guard mkdir(destination.path,0o700)==0 else { throw Failure.io(operation:"create destination",code:errno) }
        let rootFD=open(destination.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
        guard rootFD>=0 else { throw Failure.io(operation:"open destination",code:errno) };defer { close(rootFD) }
        let cancellation=Cancellation { cancelled() || Task.isCancelled }
        let pointer=Unmanaged.passUnretained(cancellation).toOpaque()
        var results:[Entry]=[]
        for member in members {
            try check()
            let path=member.directory ? String(member.path.dropLast()) : member.path
            let out=oz_create_member(rootFD,path,member.directory ? 1 : 0)
            guard out>=0 else { throw Failure.io(operation:"create member",code:errno) }
            let code: Int32
            if member.directory { code=fsync(out)==0 ? 0:1 }
            else {
                code=oz_extract(sourceFD,out,member.dataOffset,member.compressed,member.expanded,member.crc,Int32(member.method),{ raw in
                    guard let raw else { return 1 }
                    return Unmanaged<Cancellation>.fromOpaque(raw).takeUnretainedValue().check() ? 1 : 0
                },pointer)
            }
            close(out)
            guard code==0 else { throw code==3 ? Failure.cancelled : (code==1 ? Failure.io(operation:"extract member",code:errno) : Failure.invalidArchive) }
            results.append(Entry(path:member.path,bytes:member.expanded,crc32:member.crc))
        }
        var final=stat();guard fstat(sourceFD,&final)==0, final.st_size==original.st_size,
            sameTimes(final,original) else { throw Failure.invalidArchive }
        guard fsync(rootFD)==0 else { throw Failure.io(operation:"flush destination",code:errno) };try check();return results
    }
    private static func sameTimes(_ a:stat,_ b:stat)->Bool {
        #if canImport(Darwin)
        return a.st_mtimespec.tv_sec==b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec==b.st_mtimespec.tv_nsec && a.st_ctimespec.tv_sec==b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec==b.st_ctimespec.tv_nsec
        #else
        return a.st_mtim.tv_sec==b.st_mtim.tv_sec && a.st_mtim.tv_nsec==b.st_mtim.tv_nsec && a.st_ctim.tv_sec==b.st_ctim.tv_sec && a.st_ctim.tv_nsec==b.st_ctim.tv_nsec
        #endif
    }
    private struct Reader {
        let fd:Int32;let size:UInt64
        func read(_ offset:UInt64,_ count:Int) throws -> Data {
            guard count>=0, offset<=size, UInt64(count)<=size-offset, offset<=UInt64(Int64.max) else { throw Failure.invalidArchive }
            var data=Data(count:count)
            try data.withUnsafeMutableBytes { raw in
                var done=0
                while done<count {
                    let n=pread(fd,raw.baseAddress!.advanced(by:done),count-done,off_t(offset)+off_t(done))
                    if n<0 && errno==EINTR { continue }
                    guard n>0 else { throw Failure.io(operation:"read metadata",code:errno) };done+=n
                }
            }
            return data
        }
    }
    private static func centralDirectory(_ file:Reader,limits:Limits) throws -> (offset:UInt64,size:UInt64,count:Int) {
        let tail=try file.read(file.size-min(file.size,65_557),Int(min(file.size,65_557)))
        var found:Int?
        for index in stride(from:tail.count-22,through:0,by:-1) where tail.u32(index)==0x06054b50 {
            if index+22+Int(tail.u16(index+20))==tail.count { found=index;break }
        }
        guard let index=found else { throw Failure.invalidArchive }
        let endOffset=file.size-UInt64(tail.count)+UInt64(index)
        guard tail.u16(index+4)==0,tail.u16(index+6)==0,tail.u16(index+8)==tail.u16(index+10) else { throw Failure.unsupported }
        var count=UInt64(tail.u16(index+10)),size=UInt64(tail.u32(index+12)),offset=UInt64(tail.u32(index+16)),boundary=endOffset
        if count==0xffff || size==0xffffffff || offset==0xffffffff {
            guard endOffset>=20 else { throw Failure.invalidArchive }
            let locator=try file.read(endOffset-20,20)
            guard locator.u32(0)==0x07064b50,locator.u32(4)==0,locator.u32(16)==1 else { throw Failure.unsupported }
            let position=locator.u64(8),header=try file.read(position,56)
            guard header.u32(0)==0x06064b50,header.u64(4)>=44,header.u64(4)<=1_000_000,
                position<=endOffset-20,header.u64(4)+12==endOffset-20-position,
                header.u32(16)==0,header.u32(20)==0,header.u64(24)==header.u64(32) else { throw Failure.invalidArchive }
            count=header.u64(32);size=header.u64(40);offset=header.u64(48);boundary=position
        }
        guard count<=UInt64(limits.entries),size<=limits.centralDirectoryBytes else { throw Failure.limit }
        guard offset<=boundary,size<=boundary-offset,offset+size==boundary else { throw Failure.invalidArchive }
        return (offset,size,Int(count))
    }
    private static func parseMembers(_ file:Reader,central:UInt64,length:UInt64,count:Int,limits:Limits) throws -> [Member] {
        var cursor=central,members:[Member]=[],total:UInt64=0
        for _ in 0..<count {
            try Task.checkCancellation()
            guard cursor<=central+length,central+length-cursor>=46 else { throw Failure.invalidArchive }
            let header=try file.read(cursor,46)
            guard header.u32(0)==0x02014b50 else { throw Failure.invalidArchive }
            let flags=header.u16(8),method=header.u16(10)
            guard flags & ~UInt16(0x080e)==0,method==0 || method==8,header.u16(34)==0 else { throw Failure.unsupported }
            let nameLength=Int(header.u16(28)),extraLength=Int(header.u16(30)),commentLength=Int(header.u16(32))
            let full=46+nameLength+extraLength+commentLength
            guard UInt64(full)<=central+length-cursor else { throw Failure.invalidArchive }
            let fields=try file.read(cursor+46,nameLength+extraLength)
            guard let name=String(data:fields.prefix(nameLength),encoding:.utf8),!name.isEmpty else { throw Failure.unsupported }
            let directory=name.hasSuffix("/"),mode=header.u32(38)>>16,kind=mode & 0xf000
            guard kind==0 || kind==(directory ? 0x4000:0x8000) else { throw Failure.unsupported }
            guard (header.u32(38)&0x10)==0 || directory else { throw Failure.invalidArchive }
            var expanded=UInt64(header.u32(24)),compressed=UInt64(header.u32(20)),offset=UInt64(header.u32(42))
            let wide=expanded==0xffffffff || compressed==0xffffffff
            let z64=try zip64(Data(fields.suffix(extraLength)))
            var zcursor=0
            func next() throws -> UInt64 { guard let z64,zcursor+8<=z64.count else { throw Failure.invalidArchive };defer { zcursor+=8 };return z64.u64(zcursor) }
            if expanded==0xffffffff { expanded=try next() }
            if compressed==0xffffffff { compressed=try next() }
            if offset==0xffffffff { offset=try next() }
            guard expanded<=limits.memberBytes,expanded<=limits.totalBytes-total else { throw Failure.limit };total+=expanded
            guard compressed<=file.size,offset<central,(!directory || (expanded==0 && compressed==0 && header.u32(16)==0 && method==0)),method != 0 || compressed==expanded else { throw Failure.invalidArchive }
            members.append(Member(path:name,directory:directory,method:method,flags:flags,compressed:compressed,expanded:expanded,crc:header.u32(16),offset:offset,zip64Sizes:wide))
            cursor+=UInt64(full)
        }
        guard cursor==central+length else { throw Failure.invalidArchive };return members
    }
    private static func zip64(_ data:Data) throws -> Data? {
        var cursor=0,result:Data?
        while cursor<data.count {
            guard data.count-cursor>=4 else { throw Failure.invalidArchive }
            let id=data.u16(cursor),length=Int(data.u16(cursor+2));cursor+=4
            guard length<=data.count-cursor else { throw Failure.invalidArchive }
            if id==1 { guard result==nil else { throw Failure.invalidArchive };result=Data(data[cursor..<cursor+length]) }
            cursor+=length
        }
        return result
    }
    private static func validateLocal(_ file:Reader,member:Member,centralOffset:UInt64) throws -> Member {
        let header=try file.read(member.offset,30)
        guard header.u32(0)==0x04034b50,header.u16(6)==member.flags,header.u16(8)==member.method else { throw Failure.invalidArchive }
        let nameLength=Int(header.u16(26)),extraLength=Int(header.u16(28))
        let fields=try file.read(member.offset+30,nameLength+extraLength)
        guard Data(fields.prefix(nameLength))==Data(member.path.utf8) else { throw Failure.invalidArchive }
        let dataOffset=member.offset+30+UInt64(nameLength+extraLength)
        guard dataOffset<=centralOffset,member.compressed<=centralOffset-dataOffset else { throw Failure.invalidArchive }
        let extra=try zip64(Data(fields.suffix(extraLength)))
        var expanded=UInt64(header.u32(22)),compressed=UInt64(header.u32(18)),cursor=0
        let localWide=expanded==0xffffffff || compressed==0xffffffff
        func next() throws -> UInt64 { guard let extra,cursor+8<=extra.count else { throw Failure.invalidArchive };defer { cursor+=8 };return extra.u64(cursor) }
        if expanded==0xffffffff { expanded=try next() };if compressed==0xffffffff { compressed=try next() }
        let descriptor=member.flags&8 != 0
        if descriptor {
            guard (header.u32(14)==0 || header.u32(14)==member.crc), (expanded==0 || expanded==member.expanded),(compressed==0 || compressed==member.compressed) else { throw Failure.invalidArchive }
        } else { guard header.u32(14)==member.crc,expanded==member.expanded,compressed==member.compressed else { throw Failure.invalidArchive } }
        var end=dataOffset+member.compressed
        if descriptor {
            let wide=member.zip64Sizes || localWide,base=wide ? 20:12
            guard end<=centralOffset,UInt64(base)<=centralOffset-end else { throw Failure.invalidArchive }
            let bytes=try file.read(end,Int(min(UInt64(base+4),centralOffset-end)))
            func matches(_ at:Int)->Bool {
                guard bytes.count>=at+base,bytes.u32(at)==member.crc else { return false }
                return wide ? (bytes.u64(at+4)==member.compressed && bytes.u64(at+12)==member.expanded) : (UInt64(bytes.u32(at+4))==member.compressed && UInt64(bytes.u32(at+8))==member.expanded)
            }
            if bytes.u32(0)==0x08074b50 && matches(4) { end+=UInt64(base+4) }
            else if matches(0) { end+=UInt64(base) }
            else { throw Failure.invalidArchive }
        }
        var result=member;result.dataOffset=dataOffset;result.end=end;return result
    }
    private static func normalizedPath(_ path:String,directory:Bool) throws -> String {
        let clean=directory ? String(path.dropLast()):path
        guard !clean.isEmpty,clean.utf8.count<=4096,!clean.hasPrefix("/"),!clean.contains("\\"),!clean.contains(":"),
              !clean.unicodeScalars.contains(where:{CharacterSet.controlCharacters.contains($0)}) else { throw Failure.unsafePath }
        let parts=clean.split(separator:"/",omittingEmptySubsequences:false)
        guard parts.allSatisfy({!$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.count<=255}) else { throw Failure.unsafePath }
        return clean.precomposedStringWithCanonicalMapping.lowercased()
    }
}
private extension Data {
    func u16(_ p:Int)->UInt16 { UInt16(self[p]) | UInt16(self[p+1])<<8 }
    func u32(_ p:Int)->UInt32 { UInt32(u16(p)) | UInt32(u16(p+2))<<16 }
    func u64(_ p:Int)->UInt64 { UInt64(u32(p)) | UInt64(u32(p+4))<<32 }
}
