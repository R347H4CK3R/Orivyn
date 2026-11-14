import Foundation
@main struct Checks {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let valid=root.appendingPathComponent("valid"),link=root.appendingPathComponent("link"),large=root.appendingPathComponent("large")
        try Data([1,2,3]).write(to:valid)
        let actual = try VisionImageFile.read(valid); precondition(actual == Data([1,2,3]))
        try FileManager.default.createSymbolicLink(at:link,withDestinationURL:valid)
        do { _ = try VisionImageFile.read(link);fatalError("symlink") } catch { }
        do { _ = try VisionImageFile.read(root);fatalError("directory") } catch { }
        try Data(repeating:0,count:10*1024*1024+1).write(to:large)
        do { _ = try VisionImageFile.read(large);fatalError("oversize") } catch { }
        try Data().write(to:valid)
        do { _ = try VisionImageFile.read(valid);fatalError("empty") } catch { }
        do { _ = try VisionImageFile.read(URL(string:"https://example.com/image")!);fatalError("remote") } catch { }
        print("PASS 6 actual owned image-file read cases")
    }
}
