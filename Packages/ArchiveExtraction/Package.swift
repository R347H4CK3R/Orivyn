// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ArchiveExtraction", platforms: [.iOS(.v17), .macOS(.v13)], products: [.library(name: "ArchiveExtraction", targets: ["ArchiveExtraction"])], targets: [.target(name: "CArchive", publicHeadersPath: "include", linkerSettings: [.linkedLibrary("z")]), .target(name: "ArchiveExtraction", dependencies: ["CArchive"]), .testTarget(name: "ArchiveExtractionTests", dependencies: ["ArchiveExtraction"])])
