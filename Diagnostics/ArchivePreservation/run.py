#!/usr/bin/env python3
"""Build exact preservation source/tests in a disposable Swift package; no private data."""
import pathlib, sys, subprocess, shutil, json, zipfile, hashlib, runpy, os, base64
root=pathlib.Path(__file__).resolve().parents[2]
out=pathlib.Path(sys.argv[2]).resolve();out.mkdir(parents=True,exist_ok=False)
for directory in ['Sources/Preservation','Tests/PreservationTests']:(out/directory).mkdir(parents=True)
shutil.copyfile(root/'JarvisEVO/Services/ArchivePreservation.swift',out/'Sources/Preservation/ArchivePreservation.swift')
shutil.copyfile(root/'JarvisEVO/Core/ArchiveReadBuffer.swift',out/'Sources/Preservation/ArchiveReadBuffer.swift')
shutil.copyfile(root/'Tests/ArchivePreservationTests.swift',out/'Tests/PreservationTests/ArchivePreservationTests.swift')
# An optional fourth argument enables component integration with a snapshot of
# the actual extractor package, never a stub or a private archive fixture.
extra_dependency = ''; extra_test_dependency = ''; resources = ''
if len(sys.argv) > 3:
 extractor = pathlib.Path(sys.argv[3]).resolve()
 shutil.copytree(extractor, out/'ArchiveExtraction', ignore=shutil.ignore_patterns('.build', '.swiftpm'))
 shutil.copyfile(root/'Diagnostics/ArchivePreservation/ArchivePipelineIntegrationTests.swift',out/'Tests/PreservationTests/ArchivePipelineIntegrationTests.swift')
 shutil.copyfile(root/'Diagnostics/ArchivePreservation/ArchiveRestoreServiceTests.swift',out/'Tests/PreservationTests/ArchiveRestoreServiceTests.swift')
 shutil.copyfile(root/'JarvisEVO/Services/ArchiveRestoreRecovery.swift',out/'Sources/Preservation/ArchiveRestoreRecovery.swift')
 shutil.copyfile(root/'JarvisEVO/Services/ArchiveRestoreService.swift',out/'Sources/Preservation/ArchiveRestoreService.swift')
 for name in ['Conversation.swift','MemoryNote.swift','ImageOCRResult.swift','OCRLineEvidence.swift','ChatGPTConversationRestore.swift','ChatGPTRecordStream.swift','ArchiveRestoreProgress.swift','ArchiveRestoreInventory.swift']:
  shutil.copyfile(root/'JarvisEVO/Core'/name,out/'Sources/Preservation'/name)
 fixtures=out/'Tests/PreservationTests/Fixtures'; fixtures.mkdir()
 conversation = [{"id":"00000000-0000-0000-0000-000000000101", "title":"Synthetic import", "create_time":100.0, "update_time":101.0, "current_node":"leaf", "mapping":{"leaf":{"parent":None, "message":{"id":"00000000-0000-0000-0000-000000000102", "create_time":101.0, "status":"finished_successfully", "author":{"role":"user"}, "content":{"content_type":"text", "parts":["Synthetic saved question"]}}}}}]
 conversation[0]['mapping']['reply']={'parent':'leaf','message':{'id':'00000000-0000-0000-0000-000000000103','create_time':102.0,'status':'finished_successfully','author':{'role':'assistant'},'channel':'final','recipient':'all','content':{'content_type':'text','parts':['Synthetic saved answer']}}}
 conversation[0]['current_node']='reply'; conversation[0]['update_time']=102.0
 conversation_bytes=json.dumps(conversation,sort_keys=True,separators=(',',':')).encode('utf-8')
 with zipfile.ZipFile(fixtures/'valid.zip','w') as archive:
  for name, data, method in [('conversation.txt',b'Synthetic conversation, not private history.\n',zipfile.ZIP_STORED),('assets/repeated.bin',b'a'*300000,zipfile.ZIP_DEFLATED),('conversations.json',conversation_bytes,zipfile.ZIP_DEFLATED)]:
   info=zipfile.ZipInfo(name,date_time=(2026,1,1,0,0,0)); info.compress_type=method; info.external_attr=0o100600 << 16; archive.writestr(info,data)
 corrupt=bytearray((fixtures/'valid.zip').read_bytes()); pos=corrupt.index(b'Synthetic conversation'); corrupt[pos] ^= 1; (fixtures/'crc-failure.zip').write_bytes(corrupt)
 # Synthetic near-limit plan is generated outside the measured Swift process.
 # This fixture is metadata-only: no original-file existence or activation claim.
 inventory_root=fixtures/'inventory-resource'
 job_id='00000000-0000-0000-0000-000000000301'
 job=inventory_root/job_id; job.mkdir(parents=True)
 messages=[]; unresolved=[]
 opaque=base64.b64encode(b'x'*1000).decode()
 for index in range(20_000):
  message_id='00000000-0000-0000-0000-'+format(index+100001,'012d')
  messages.append({'id':message_id,'role':'user','content':'s'*750,'createdAt':0,'state':'complete','attachments':[]})
  unresolved.append({'messageID':message_id,'source':'contentPart','originalJSON':opaque})
 plan={'expectedEpoch':'00000000-0000-0000-0000-000000000302',
       'conversations':[{'id':'00000000-0000-0000-0000-000000000303','title':'Synthetic large retained inventory',
                         'createdAt':0,'updatedAt':0,'isArchived':False,'messages':messages}], 'unresolved':unresolved}
 plan_path=job/'plan.json'
 with plan_path.open('w') as stream:
  for chunk in json.JSONEncoder(separators=(',',':')).iterencode(plan):stream.write(chunk)
 assert 35_000_000 < plan_path.stat().st_size < 50_000_000
 sha=hashlib.sha256()
 with plan_path.open('rb') as stream:
  for chunk in iter(lambda:stream.read(1048576),b''):sha.update(chunk)
 review={'jobID':job_id,'conversationCount':1,'messageCount':20000,'unresolvedCount':20000,'omittedCount':0,'retainedFileCount':0,'archiveSHA256':'a'*64}
 state={'version':1,'jobID':job_id,'phase':'reviewReady','original':{'version':1,'bytes':0,'sha256':'a'*64},
        'review':review,'planSHA256':sha.hexdigest(),'events':[]}
 (job/'state.json').write_text(json.dumps(state,separators=(',',':')))
 del messages,unresolved,plan
 extra_dependency = ', .package(path: "ArchiveExtraction")'
 extra_test_dependency = ', .product(name: "ArchiveExtraction", package: "ArchiveExtraction")'
 resources = ', resources: [.copy("Fixtures")]'
sqlite_dependency = ''; sqlite_target = ''
# Apple's SDK exposes SQLite3 even without an amalgamation argument, enabling
# the conditional SQLite integration tests. Copy their exact production inputs.
if len(sys.argv) > 4 or (sys.platform == 'darwin' and len(sys.argv) > 3):
 for name in runpy.run_path(str(root/'scripts/run_persistence_tests.py'))['SOURCES']:
  shutil.copyfile(root/name, out/'Sources/Preservation'/pathlib.Path(name).name)
if len(sys.argv) > 4:
 sqlite_source = pathlib.Path(sys.argv[4]).resolve()
 sqlite_dir = out/'Sources/SQLite3'; (sqlite_dir/'include').mkdir(parents=True)
 shutil.copyfile(sqlite_source/'sqlite3.c',sqlite_dir/'sqlite3.c')
 shutil.copyfile(sqlite_source/'sqlite3.h',sqlite_dir/'include/sqlite3.h')
 sqlite_dependency = ', "SQLite3"'
 sqlite_target = '.target(name:"SQLite3",publicHeadersPath:"include",cSettings:[.define("SQLITE_THREADSAFE",to:"1")],linkerSettings:[.linkedLibrary("dl"),.linkedLibrary("m")]),'
# Native macOS needs no package download: CryptoKit and SQLite3 come from the SDK.
crypto_package = '' if sys.platform == 'darwin' else '.package(url: "https://github.com/apple/swift-crypto.git", exact: "3.0.0")'
crypto_product = '' if sys.platform == 'darwin' else '.product(name: "Crypto", package: "swift-crypto")'
dependencies = ', '.join(x for x in [crypto_package,extra_dependency.lstrip(', ')] if x)
products = ', '.join(x for x in [crypto_product,extra_test_dependency.lstrip(', '),sqlite_dependency.lstrip(', ')] if x)
(out/'Package.swift').write_text(f'''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Preservation", dependencies: [{dependencies}], targets: [{sqlite_target}.target(name: "Preservation", dependencies: [{products}]), .testTarget(name: "PreservationTests", dependencies: [.target(name: "Preservation"){extra_test_dependency}]{resources})])
''')
def sha_file(path):
 digest=hashlib.sha256()
 with path.open('rb') as stream:
  for chunk in iter(lambda:stream.read(1048576),b''):digest.update(chunk)
 return digest.hexdigest()
(out/'SOURCE-MANIFEST.json').write_text(json.dumps([{'path':str(p.relative_to(out)),'sha256':sha_file(p)} for p in sorted(out.rglob('*')) if p.is_file()],indent=2)+'\n')
command=[sys.argv[1],'test','--jobs','2','--package-path',str(out)]
(out/'COMMAND.json').write_text(json.dumps(command,indent=2)+'\n')
env=dict(os.environ,CLANG_MODULE_CACHE_PATH=str(out/'.clang-cache'),SWIFTPM_MODULECACHE_OVERRIDE=str(out/'.module-cache'),TMPDIR=str(out/'tmp'))
(out/'tmp').mkdir()
result=subprocess.call(command,env=env)
(out/'RESULT.json').write_text(json.dumps({'exit':result,'hostPlatform':sys.platform,'iPhoneVerified':False,'systemSQLite':sys.platform=='darwin' and len(sys.argv)<=4},indent=2)+'\n')
sys.exit(result)
