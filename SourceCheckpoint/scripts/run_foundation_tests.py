#!/usr/bin/env python3
"""Run exact Foundation-only production Swift/tests, never the iOS application.
Requires an already-installed Swift6 toolchain; does not download or dispatch CI.
"""
import argparse, hashlib, json, os, pathlib, subprocess, sys
SOURCES = [
 'JarvisEVO/Core/AttachmentTextSearch.swift',
 'JarvisEVO/Core/LocalSearchExcerpt.swift',
 'JarvisEVO/Providers/Local/UTF8TokenAccumulator.swift',
]
TESTS = ['Tests/AttachmentTextSearchTests.swift','Tests/LocalSearchExcerptTests.swift','Tests/UTF8TokenAccumulatorTests.swift']
PACKAGE = '''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "OrivynFoundationProof", products: [.library(name: "JarvisEVO", targets: ["JarvisEVO"])], targets: [.target(name: "JarvisEVO"), .testTarget(name: "JarvisEVOTests", dependencies: ["JarvisEVO"])])
'''
def prepare(root, output):
 output.mkdir(parents=True, exist_ok=False)
 manifest=[]
 for group, destination in [(SOURCES,'Sources/JarvisEVO'),(TESTS,'Tests/JarvisEVOTests')]:
  folder=output/destination;folder.mkdir(parents=True)
  for name in group:
   data=(root/name).read_bytes();(folder/pathlib.Path(name).name).write_bytes(data)
   manifest.append({'source':name,'sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data)})
 (output/'Package.swift').write_text(PACKAGE)
 (output/'SOURCE-MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n')
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--swift',required=True);p.add_argument('--output',type=pathlib.Path,required=True);a=p.parse_args()
 root=pathlib.Path(__file__).resolve().parents[1];output=a.output.resolve();prepare(root,output)
 env=dict(os.environ, CLANG_MODULE_CACHE_PATH=str(output/'.clang-cache'), SWIFTPM_MODULECACHE_OVERRIDE=str(output/'.module-cache'))
 with (output/'swift-test.log').open('w') as log:
  version=subprocess.run([a.swift,'--version'],stdout=log,stderr=subprocess.STDOUT)
  if version.returncode:return version.returncode
  result=subprocess.run([a.swift,'test','--jobs','2','--package-path',str(output),'--cache-path',str(output/'.cache'),'--config-path',str(output/'.config'),'--security-path',str(output/'.security')],stdout=log,stderr=subprocess.STDOUT,env=env)
 print((output/'swift-test.log').read_text())
 print('Foundation-only Swift test exit:',result.returncode,'; iOS build/device validation NOT performed.')
 return result.returncode
if __name__=='__main__':sys.exit(main())
