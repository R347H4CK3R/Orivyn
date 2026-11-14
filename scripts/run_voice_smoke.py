#!/usr/bin/env python3
"""Compile exact production voice controller with official static Swift Observation.
Controlled audio/provider boundaries only: NOT microphone, TTS, model, Apple API or iPhone testing.
"""
import argparse,hashlib,json,os,pathlib,subprocess,time
SOURCES=['JarvisEVO/Core/VoiceError.swift','JarvisEVO/Services/VoiceConversationController.swift','scripts/swift-smoke/VoiceSmoke.swift']
EXTRACTED_ENUM_SHA256='74e2b832ff745a3688a80691b17908fe7d05447f32ae738c5502d5b31412611d'
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--swiftc',required=True);p.add_argument('--output',required=True,type=pathlib.Path);a=p.parse_args()
 root=pathlib.Path(__file__).resolve().parents[1];out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
 manifest=[];files=[]
 for name in SOURCES:
  data=(root/name).read_bytes();dest=out/pathlib.Path(name).name;dest.write_bytes(data);files.append(str(dest));manifest.append({'source':name,'sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data),'compiledUnchanged':True})
 (out/'SOURCE-MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n')
 enum=(root/SOURCES[0]).read_text().removeprefix('import Foundation\n\n').rstrip('\n')
 definitions=[str(x.relative_to(root)) for x in (root/'JarvisEVO').rglob('*.swift') if 'enum VoiceError:' in x.read_text()]
 parity={'enumSHA256':hashlib.sha256(enum.encode()).hexdigest(),'originalExtractedEnumSHA256':EXTRACTED_ENUM_SHA256,'unchangedEnum':hashlib.sha256(enum.encode()).hexdigest()==EXTRACTED_ENUM_SHA256,'definitionFiles':definitions}
 (out/'EXTRACTION-PARITY.json').write_text(json.dumps(parity,indent=2)+'\n')
 if not parity['unchangedEnum'] or definitions!=[SOURCES[0]]:raise SystemExit('VoiceError extraction parity/unique definition failed')
 env=dict(os.environ,HOME=str(out/'home'),XDG_CONFIG_HOME=str(out/'config'),TMPDIR=str(out/'tmp'))
 for name in ['home','config','tmp']:(out/name).mkdir()
 version=subprocess.run([a.swiftc,'--version'],env=env,capture_output=True,text=True,check=True);(out/'TOOLCHAIN.txt').write_text(version.stdout+version.stderr)
 command=[a.swiftc,'-swift-version','6','-parse-as-library','-static-stdlib','-module-cache-path',str(out/'module-cache'),*files,'-o',str(out/'voice-smoke')]
 (out/'COMMAND.json').write_text(json.dumps(command,indent=2)+'\n');started=time.monotonic();compile_code=runtime_code=None
 try:
  with (out/'smoke.log').open('w') as log:
   result=subprocess.run(command,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=180);compile_code=result.returncode
   if compile_code==0:result=subprocess.run([str(out/'voice-smoke')],env=env,stdout=log,stderr=subprocess.STDOUT,timeout=30);runtime_code=result.returncode
 finally:
  report={'compileExit':compile_code,'runtimeExit':runtime_code,'elapsedSeconds':time.monotonic()-started,'exactProductionController':True,'staticOfficialSwiftObservation':True,'boundaryDoubles':['VoiceConversationAudio','sendText/cancelResponse'],'microphoneVerified':False,'TTSVerified':False,'modelVerified':False,'AppleAPIsVerified':False,'nativeIPhoneVerified':False}
  (out/'RESULT.json').write_text(json.dumps(report,indent=2)+'\n')
 print((out/'smoke.log').read_text());return result.returncode
if __name__=='__main__':raise SystemExit(main())
