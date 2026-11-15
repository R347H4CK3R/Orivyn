#!/usr/bin/env python3
"""Prepare byte-identical production component tests for macOS, not iOS/AppModel."""
import argparse, hashlib, json
from pathlib import Path
from run_persistence_tests import SOURCES, TESTS

EXTRA_SOURCES = ['JarvisEVO/Core/BackupImportConfirmation.swift', 'JarvisEVO/Services/BackupFileReader.swift']
EXTRA_TESTS = ['Tests/BackupImportConfirmationTests.swift', 'Tests/BackupFileReaderTests.swift']
PACKAGE = '''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "BackupHostProof", platforms: [.macOS(.v14)], targets: [
 .target(name: "JarvisEVO", linkerSettings: [.linkedLibrary("sqlite3")]),
 .testTarget(name: "JarvisEVOTests", dependencies: ["JarvisEVO"])
])
'''
def prepare(root, output):
    output.mkdir(parents=True, exist_ok=False)
    manifest=[]
    for names, folder in [(SOURCES+EXTRA_SOURCES,'Sources/JarvisEVO'), (TESTS+EXTRA_TESTS,'Tests/JarvisEVOTests')]:
        target=output/folder; target.mkdir(parents=True)
        for name in names:
            data=(root/name).read_bytes(); (target/Path(name).name).write_bytes(data)
            manifest.append(dict(source=name,sha256=hashlib.sha256(data).hexdigest()))
    (output/'Package.swift').write_text(PACKAGE)
    (output/'SOURCE-MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n')
    (output/'SCOPE.txt').write_text('macOS host components only: exact confirmation, coordinated Darwin reader, SQLite persistence tests. Not AppModel integration, iOS picker, external provider authorization, or device verification.\n')
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__); p.add_argument('--output',required=True,type=Path); a=p.parse_args()
    prepare(Path(__file__).resolve().parents[1],a.output)
