#!/usr/bin/env python3
"""Exact startGeneration method regression with explicit store/provider boundary doubles. Not an Apple/UI test."""
import pathlib,subprocess,sys,hashlib,json,argparse
parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--swiftc',required=True);parser.add_argument('--output',required=True);args=parser.parse_args()
root=pathlib.Path(__file__).resolve().parents[1]; out=pathlib.Path(args.output).resolve(); out.mkdir(parents=True,exist_ok=False)
raw=(root/'JarvisEVO/UI/AppModel.swift').read_text(); start=raw.index('    private func startGeneration('); end=raw.index('\n    }\n',start)+6; method=raw[start:end]
template=(root/'scripts/swift-smoke/GenerationContextSmoke.swift').read_text(); template=template.replace('// PRODUCTION_METHOD',method).replace('/* PROVIDER_ID */',', providerID: actual' if 'providerID: String' in method.split('->')[0] else '')
(out/'driver.swift').write_text(template); (out/'SOURCE.json').write_text(json.dumps({'appModelSHA256':hashlib.sha256(raw.encode()).hexdigest(),'extractedMethodSHA256':hashlib.sha256(method.encode()).hexdigest(),'scope':'Exact startGeneration; store and provider doubles; AppSelfKnowledge and conversation models compiled unchanged'},indent=2))
swift=args.swiftc
files=[str(root/'JarvisEVO/Core'/f) for f in ['Conversation.swift','ImageOCRResult.swift','OCRLineEvidence.swift','AppSelfKnowledge.swift']]
command=[swift,'-swift-version','6','-parse-as-library','-module-cache-path',str(out/'cache'),*files,str(out/'driver.swift'),'-o',str(out/'test')]
r=subprocess.run(command,capture_output=True,text=True);(out/'compile.log').write_text(r.stdout+r.stderr)
if r.returncode: print(r.stderr);sys.exit(r.returncode)
r=subprocess.run([str(out/'test')],capture_output=True,text=True);(out/'results.log').write_text(r.stdout+r.stderr);print(r.stdout+r.stderr);sys.exit(r.returncode)
