// swift-tools-version: 6.0
import PackageDescription

// Run scripts/bootstrap_llama.sh before opening/building the Xcode project.
// The official release archive is checksum-verified and contains device + simulator.
let package = Package(
    name: "LlamaRuntime",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "LlamaRuntime", targets: ["llama"])],
    targets: [.binaryTarget(name: "llama", path: "Frameworks/llama.xcframework")]
)
