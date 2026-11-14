#!/usr/bin/env python3
"""Execute exact extracted ReminderScheduler/declarations with explicit boundary doubles.
Real Observation runtime; controlled notification boundary only, not OS delivery.
No production source changes.
"""
import argparse,hashlib,json,pathlib,subprocess,os

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--swiftc',required=True);p.add_argument('--output',required=True,type=pathlib.Path);a=p.parse_args()
 root=pathlib.Path(__file__).resolve().parents[1];out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
 source=root/'JarvisEVO/Services/ReminderScheduler.swift';raw=source.read_text()
 start=raw.index('enum ReminderAuthorization:');end=raw.index('@MainActor\nfinal class SystemReminderNotifications:')
 declarations=raw[start:end]
 scheduler=raw[raw.index('@MainActor @Observable\nfinal class ReminderScheduler:'):] if '@MainActor @Observable\nfinal class ReminderScheduler:' in raw else raw[raw.index('@MainActor @Observable\nfinal class ReminderScheduler {'):]
 extracted='import Foundation\nimport Observation\n\n'+declarations+scheduler
 method_start=raw.index('    nonisolated private static func components(for date: Date) -> DateComponents {')
 method_end=raw.index('\n    }',method_start)+len('\n    }')
 components=raw[method_start:method_end]
 wrapper='import Foundation\nenum ProductionReminderComponents {\n'+components+'\n    static func evaluate(_ date: Date) -> DateComponents { components(for: date) }\n}\n'
 (out/'ProductionReminderComponents.swift').write_text(wrapper)
 (out/'ReminderSchedulerExtracted.swift').write_text(extracted)
 manifest=[{'source':'JarvisEVO/Services/ReminderScheduler.swift','sha256':hashlib.sha256(source.read_bytes()).hexdigest()}, {'extracted':'ReminderSchedulerExtracted.swift','sha256':hashlib.sha256(extracted.encode()).hexdigest(),'declarationsExact':declarations in raw,'schedulerExact':scheduler in raw,'excluded':'SystemReminderNotifications Apple adapter'}]
 manifest.append({'extracted':'components(for:)','sha256':hashlib.sha256(components.encode()).hexdigest(),'exactSubstringOfProduction':components in raw,'wrapperOnly':'internal test entrypoint calls unchanged private method'})
 files=[str(out/'ReminderSchedulerExtracted.swift'),str(out/'ProductionReminderComponents.swift')]
 for name in ['JarvisEVO/Core/LocalReminder.swift']:
  b=(root/name).read_bytes();dest=out/pathlib.Path(name).name;dest.write_bytes(b);files.append(str(dest));manifest.append({'source':name,'sha256':hashlib.sha256(b).hexdigest(),'compiledUnchanged':True})
 template=(root/'scripts/swift-smoke/ReminderSmoke.swift').read_text();driver=template
 (out/'ReminderSmoke.swift').write_text(driver);files.append(str(out/'ReminderSmoke.swift'));manifest.append({'source':'scripts/swift-smoke/ReminderSmoke.swift','sha256':hashlib.sha256(template.encode()).hexdigest(),'explicitBoundaryDoubles':True})
 (out/'SOURCE-MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n')
 env=dict(os.environ,HOME=str(out/'home'),TMPDIR=str(out/'tmp'))
 for n in ['home','tmp']:(out/n).mkdir()
 version=subprocess.run([a.swiftc,'--version'],capture_output=True,text=True,check=True);(out/'TOOLCHAIN.txt').write_text(version.stdout+version.stderr)
 command=[a.swiftc,'-swift-version','6','-parse-as-library','-static-stdlib','-module-cache-path',str(out/'module-cache'),*files,'-o',str(out/'reminder-smoke')];(out/'COMMAND.json').write_text(json.dumps(command,indent=2)+'\n')
 with (out/'compile.log').open('w') as log:r=subprocess.run(command,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=120)
 report={'compileExit':r.returncode,'runExit':None}
 if r.returncode==0:
  r=subprocess.run([str(out/'reminder-smoke')],env=env,capture_output=True,text=True,timeout=30);(out/'result.json').write_text(r.stdout);(out/'runtime-stderr.txt').write_text(r.stderr);report['runExit']=r.returncode
 (out/'STATUS.json').write_text(json.dumps(report,indent=2)+'\n');print((out/'compile.log').read_text());print((out/'result.json').read_text() if (out/'result.json').exists() else 'No runtime result');return r.returncode
if __name__=='__main__':raise SystemExit(main())
