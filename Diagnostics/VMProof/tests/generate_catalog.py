from pathlib import Path
import hashlib,json
root=Path(__file__).resolve().parent.parent
mime={'html':'text/html','css':'text/css','js':'text/javascript','wasm':'application/wasm','bin':'application/octet-stream'}
files=[]
for p in sorted((root/'Assets').iterdir()):
 data=p.read_bytes();files.append({'name':p.name,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'mime':mime[p.suffix[1:]]})
text='// Generated from reviewed local assets; rerun after intentional source edits.\nimport Foundation\nenum VMAssetCatalog {\n    static let files: [VMAsset] = [\n'
for x in files:text+='        VMAsset(name: '+json.dumps(x['name'])+', bytes: '+str(x['bytes'])+', sha256: '+json.dumps(x['sha256'])+', mime: '+json.dumps(x['mime'])+'),\n'
text+='    ]\n}\n'
(root/'Sources/AssetCatalog.swift').write_text(text)
(root/'ASSET_MANIFEST.json').write_text(json.dumps(files,indent=2)+'\n')
