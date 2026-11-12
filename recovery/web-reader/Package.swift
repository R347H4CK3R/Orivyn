// swift-tools-version: 6.0
import PackageDescription

// Isolated compile/test harness only. Does not change the application's project.yml or dependency graph.
let package = Package(
    name: "JarvisWebSourceFoundation",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [.library(name: "JarvisWebSourceFoundation", targets: ["JarvisEVO"])],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", exact: "1.26.0"),
        .package(url: "https://github.com/apple/swift-nio.git", exact: "2.83.0"),
        .package(url: "https://github.com/apple/swift-atomics.git", exact: "1.2.0"),
        .package(url: "https://github.com/apple/swift-collections.git", exact: "1.1.4"),
        .package(url: "https://github.com/apple/swift-system.git", exact: "1.4.0")
    ],
    targets: [
        .target(name: "JarvisEVO", dependencies: [
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "NIOHTTP1", package: "swift-nio"),
            .product(name: "NIOTransportServices", package: "swift-nio-transport-services")
        ], path: "JarvisEVO/Services/WebSources"),
        .testTarget(name: "JarvisEVOWebTests", dependencies: ["JarvisEVO", .product(name: "NIOEmbedded", package: "swift-nio")], path: "Tests", resources: [.process("Fixtures")])
    ]
)
