// swift-tools-version: 6.0
import PackageDescription
let package=Package(name:"PersistenceSystemSQLite",targets:[.systemLibrary(name:"SQLite3"),.target(name:"JarvisEVO",dependencies:["SQLite3"],linkerSettings:[.unsafeFlags(["/usr/lib/x86_64-linux-gnu/libsqlite3.so.0.8.6"])]),.testTarget(name:"JarvisEVOTests",dependencies:["JarvisEVO"])])
