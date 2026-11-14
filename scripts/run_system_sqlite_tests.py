#!/usr/bin/env python3
"""Run production persistence tests using explicitly selected installed SQLite inputs. No downloads/native Apple claim."""
import argparse,ctypes,hashlib,json,os,pathlib,re,runpy,subprocess
p=argparse.ArgumentParser()
for name in ['swift','sqlite-header','sqlite-library','output']:p.add_argument('--'+name,required=True,type=pathlib.Path)
a=p.parse_args();root=pathlib.Path(__file__).resolve().parents[1];out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
config=runpy.run_path(str(root/'scripts/run_persistence_tests.py'));manifest=[]
for names,folder in [(config['SOURCES'],'Sources/JarvisEVO'),(config['TESTS'],'Tests/JarvisEVOTests')]:
 for name in names:
  data=(root/name).read_bytes();target=out/folder/pathlib.Path(name).name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data);manifest.append({'source':name,'sha256':hashlib.sha256(data).hexdigest()})
module=out/'Sources/SQLite3';module.mkdir();header=a.sqlite_header.resolve();library=a.sqlite_library.resolve()
(module/'module.modulemap').write_text('module SQLite3 [system] { header '+json.dumps(str(header))+' export * }\n')
runtime=ctypes.CDLL(str(library));runtime.sqlite3_libversion.restype=ctypes.c_char_p
header_version=re.search(r'#define SQLITE_VERSION\s+"([^\"]+)"',header.read_text())
(out/'SQLITE-RUNTIME.json').write_text(json.dumps({'library':str(library),'runtimeVersion':runtime.sqlite3_libversion().decode(),'header':str(header),'headerVersion':header_version.group(1) if header_version else None,'appleSQLiteVerified':False},indent=2)+'\n')
for f in [header,library]:manifest.append({'source':str(f),'sha256':hashlib.sha256(f.read_bytes()).hexdigest()})
(out/'SOURCE-MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n')
(out/'Package.swift').write_text('// swift-tools-version: 6.0\nimport PackageDescription\nlet package=Package(name:"PersistenceSystemSQLite",targets:[.systemLibrary(name:"SQLite3"),.target(name:"JarvisEVO",dependencies:["SQLite3"],linkerSettings:[.unsafeFlags(['+json.dumps(str(library))+'])]),.testTarget(name:"JarvisEVOTests",dependencies:["JarvisEVO"])])\n')
command=[str(a.swift),'test','--jobs','2','--package-path',str(out),'--cache-path',str(out/'.cache'),'--config-path',str(out/'.config'),'--security-path',str(out/'.security')]
(out/'COMMAND.json').write_text(json.dumps(command,indent=2)+'\n')
with (out/'swift-test.log').open('w') as log:result=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,env=dict(os.environ,CLANG_MODULE_CACHE_PATH=str(out/'.clang-cache'),SWIFTPM_MODULECACHE_OVERRIDE=str(out/'.module-cache')))
print((out/'swift-test.log').read_text());raise SystemExit(result.returncode)
