#!/usr/bin/env python3
"""Execute exact extracted reloadProviders/replaceProviders/accessor with explicit boundary doubles.
No full AppModel, inference or iOS claim. No production source changes.
"""
import argparse,hashlib,json,pathlib,subprocess,os

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--swiftc',required=True);p.add_argument('--output',required=True,type=pathlib.Path);a=p.parse_args()
 root=pathlib.Path(__file__).resolve().parents[1];out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
 source=root/'JarvisEVO/UI/AppModel.swift';raw=source.read_text()
 def method(name):
  start=raw.index('    func '+name+'(');end=raw.index('\n    }\n',start)+len('\n    }')
  return raw[start:end]
 methods=[method('reloadProviders'),method('replaceProviders')]
 selected=next(x for x in raw.splitlines() if 'var selectedLocalAgentProvider:' in x)
 start=raw.index('struct ProviderOption:');end=raw.index('\n}\n',start)+2;option=raw[start:end]
 manifest=[{'source':'JarvisEVO/UI/AppModel.swift','sha256':hashlib.sha256(source.read_bytes()).hexdigest()}]
 for name,text in [('reloadProviders.swift',methods[0]),('replaceProviders.swift',methods[1]),('selectedLocalAgentProvider.swift',selected),('ProviderOption.swift',option)]:
  (out/name).write_text(text+'\n');manifest.append({'extracted':name,'sha256':hashlib.sha256(text.encode()).hexdigest(),'exactSubstringOfProduction':text in raw})
 files=[]
 for name in ['JarvisEVO/Providers/Local/LocalModelCatalog.swift','JarvisEVO/Providers/Local/LocalModelCatalogData.swift']:
  b=(root/name).read_bytes();dest=out/pathlib.Path(name).name;dest.write_bytes(b);files.append(str(dest));manifest.append({'source':name,'sha256':hashlib.sha256(b).hexdigest(),'compiledUnchanged':True})
 template=(root/'scripts/swift-smoke/ProviderReloadSmoke.swift').read_text();driver=template.replace('    // PRODUCTION_METHODS','\n'.join(methods+[selected]));driver=driver.replace('import Glibc','import Glibc\n\n'+option)
 (out/'ProviderReloadSmoke.swift').write_text(driver);files.append(str(out/'ProviderReloadSmoke.swift'));manifest.append({'source':'scripts/swift-smoke/ProviderReloadSmoke.swift','sha256':hashlib.sha256(template.encode()).hexdigest(),'explicitBoundaryDoubles':True})
 (out/'SOURCE-MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n')
 env=dict(os.environ,HOME=str(out/'home'),TMPDIR=str(out/'tmp'))
 for n in ['home','tmp']:(out/n).mkdir()
 version=subprocess.run([a.swiftc,'--version'],capture_output=True,text=True,check=True);(out/'TOOLCHAIN.txt').write_text(version.stdout+version.stderr)
 command=[a.swiftc,'-swift-version','6','-parse-as-library','-static-stdlib','-module-cache-path',str(out/'module-cache'),*files,'-o',str(out/'provider-reload-smoke')];(out/'COMMAND.json').write_text(json.dumps(command,indent=2)+'\n')
 with (out/'compile.log').open('w') as log:r=subprocess.run(command,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=120)
 report={'compileExit':r.returncode,'runExit':None}
 if r.returncode==0:
  r=subprocess.run([str(out/'provider-reload-smoke')],env=env,capture_output=True,text=True,timeout=30);(out/'result.json').write_text(r.stdout);(out/'runtime-stderr.txt').write_text(r.stderr);report['runExit']=r.returncode
 (out/'STATUS.json').write_text(json.dumps(report,indent=2)+'\n');print((out/'compile.log').read_text());print((out/'result.json').read_text() if (out/'result.json').exists() else 'No runtime result');return r.returncode
if __name__=='__main__':raise SystemExit(main())
