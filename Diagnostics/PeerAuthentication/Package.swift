// swift-tools-version:6.2
import PackageDescription
let package = Package(name:"NativePeerGate",platforms:[.macOS(.v15)],dependencies:[
    .package(path:"../swift-certificates"),
    .package(path:"../swift-asn1")
],targets:[
    .systemLibrary(name:"SQLite3"),
    .executableTarget(name:"NativePeerGate",dependencies:[
        "SQLite3",
        .product(name:"X509",package:"swift-certificates"),
        .product(name:"SwiftASN1",package:"swift-asn1")
    ],swiftSettings:[.define("ORIVYN_PEER_TLS_SPIKE")])
])
