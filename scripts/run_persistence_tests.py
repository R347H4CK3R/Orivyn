#!/usr/bin/env python3
"""Execute exact production conversation/SQLite tests with an explicit SQLite amalgamation.
Requires local Swift and official SQLite source inputs; never downloads or changes system packages.
"""
import argparse, hashlib, json, os, pathlib, subprocess
SOURCES = ['JarvisEVO/Core/TextRevisionPacket.swift','JarvisEVO/Core/TextRevisionEnvelope.swift','JarvisEVO/Core/ReviewedTextSnapshot.swift','JarvisEVO/Core/PeerSyncControlFrame.swift','JarvisEVO/Core/ConversationSearch.swift','JarvisEVO/Core/ImageOCRResult.swift','JarvisEVO/Core/Conversation.swift','JarvisEVO/Core/MemoryNote.swift',
 'JarvisEVO/Core/OCRLineEvidence.swift','JarvisEVO/Persistence/SQLiteConversationStore.swift']
TESTS = ['Tests/TextRevisionPacketTests.swift','Tests/TextRevisionSenderTests.swift','Tests/TextRevisionLineageTests.swift','Tests/TextPeerRevocationTests.swift','Tests/TextSendOutboxTests.swift','Tests/ReviewedTextSnapshotTests.swift','Tests/PeerSyncControlFrameTests.swift','Tests/TextReceivePersistenceTests.swift','Tests/ImageIdentityPersistenceTests.swift','Tests/PersistenceTests.swift','Tests/ConversationTests.swift','Tests/ConversationSearchTests.swift','Tests/OCRLineEvidenceTests.swift']
PACKAGE = '''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "OrivynPersistenceProof", targets: [
 .target(name: "SQLite3", publicHeadersPath: "include", cSettings: [.define("SQLITE_THREADSAFE", to: "1")], linkerSettings: [.linkedLibrary("dl"), .linkedLibrary("m")]),
 .target(name: "JarvisEVO", dependencies: ["SQLite3"]),
 .testTarget(name: "JarvisEVOTests", dependencies: ["JarvisEVO"])
])
'''
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--swift',required=True);p.add_argument('--sqlite-source',required=True,type=pathlib.Path);p.add_argument('--output',required=True,type=pathlib.Path);a=p.parse_args()
 root=pathlib.Path(__file__).resolve().parents[1];out=a.output.resolve();out.mkdir(parents=True,exist_ok=False);manifest=[]
 def copy(source,dest,label):
  b=source.read_bytes();dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(b);manifest.append({'source':label,'sha256':hashlib.sha256(b).hexdigest(),'bytes':len(b)})
 for names, folder in [(SOURCES,'Sources/JarvisEVO'),(TESTS,'Tests/JarvisEVOTests')]:
  for n in names:copy(root/n,out/folder/pathlib.Path(n).name,n)
 for n, dest in [('sqlite3.c','Sources/SQLite3/sqlite3.c'),('sqlite3.h','Sources/SQLite3/include/sqlite3.h')]:copy(a.sqlite_source/n,out/dest,'external-sqlite/'+n)
 (out/'Package.swift').write_text(PACKAGE);(out/'SOURCE-MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n')
 command=[a.swift,'test','--jobs','2','--package-path',str(out),'--cache-path',str(out/'.cache'),'--config-path',str(out/'.config'),'--security-path',str(out/'.security')]
 (out/'COMMAND.json').write_text(json.dumps(command,indent=2)+'\n')
 env=dict(os.environ,TMPDIR=str(out/'tmp'),CLANG_MODULE_CACHE_PATH=str(out/'.clang-cache'),SWIFTPM_MODULECACHE_OVERRIDE=str(out/'.module-cache'));(out/'tmp').mkdir()
 with (out/'swift-test.log').open('w') as log:result=subprocess.run(command,env=env,stdout=log,stderr=subprocess.STDOUT)
 print((out/'swift-test.log').read_text());return result.returncode
if __name__=='__main__':raise SystemExit(main())
