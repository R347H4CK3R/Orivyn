#!/usr/bin/env python3
"""Synthetic portable attachment association proof; never reads user archives."""
import pathlib, shutil, subprocess, sys, hashlib, json
root=pathlib.Path(__file__).resolve().parents[2]
out=pathlib.Path(sys.argv[2]).resolve();out.mkdir(parents=True,exist_ok=False)
for name in ['Sources/Association','Tests/AssociationTests']:(out/name).mkdir(parents=True)
shutil.copyfile(root/'JarvisEVO/Services/ArchiveAttachmentAssociation.swift',out/'Sources/Association/ArchiveAttachmentAssociation.swift')
shutil.copyfile(root/'Tests/ArchiveAttachmentAssociationTests.swift',out/'Tests/AssociationTests/ArchiveAttachmentAssociationTests.swift')
(out/'Package.swift').write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Association", dependencies: [.package(url:"https://github.com/apple/swift-crypto.git", exact:"3.0.0")], targets:[.target(name:"Association",dependencies:[.product(name:"Crypto",package:"swift-crypto")]),.testTarget(name:"AssociationTests",dependencies:["Association"])])
''')
(out/'SOURCE-MANIFEST.json').write_text(json.dumps([{'path':str(p.relative_to(out)),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(out.rglob('*')) if p.is_file()],indent=2)+'\n')
sys.exit(subprocess.call([sys.argv[1],'test','--jobs','2','--package-path',str(out)]))
