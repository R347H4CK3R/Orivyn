#!/usr/bin/env python3
"""Build exact preservation source/tests in a disposable Swift package; no private data."""
import pathlib, sys, subprocess, shutil
root=pathlib.Path(__file__).resolve().parents[2]
out=pathlib.Path(sys.argv[2]).resolve();out.mkdir(parents=True,exist_ok=False)
for directory in ['Sources/Preservation','Tests/PreservationTests']:(out/directory).mkdir(parents=True)
shutil.copyfile(root/'JarvisEVO/Services/ArchivePreservation.swift',out/'Sources/Preservation/ArchivePreservation.swift')
shutil.copyfile(root/'Tests/ArchivePreservationTests.swift',out/'Tests/PreservationTests/ArchivePreservationTests.swift')
(out/'Package.swift').write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Preservation", dependencies: [.package(url: "https://github.com/apple/swift-crypto.git", exact: "3.0.0")], targets: [.target(name: "Preservation", dependencies: [.product(name: "Crypto", package: "swift-crypto")]), .testTarget(name: "PreservationTests", dependencies: ["Preservation"])])
''')
sys.exit(subprocess.call([sys.argv[1],'test','--jobs','2','--package-path',str(out)]))
