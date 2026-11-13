from pathlib import Path
import hashlib,json
root=Path(__file__).resolve().parent.parent
manifest=json.loads((root/'ASSET_MANIFEST.json').read_text())
assert len(manifest)==15
for item in manifest:
 data=(root/'Assets'/item['name']).read_bytes()
 assert len(data)==item['bytes'] and hashlib.sha256(data).hexdigest()==item['sha256']
assert not list((root/'Assets').glob('*.iso'))
assert [p.name for p in (root/'Assets').glob('*.img')] == ['maintained.img']
assert hashlib.sha256((root/'Assets/maintained.img').read_bytes()).hexdigest() == 'c318b702448a2f08400321446719af10568a9ef878a5fe898c1cb815c1bebe72'
html=(root/'Assets/index.html').read_text()
assert "default-src 'none'" in html and "worker-src 'none'" in html
assert 'https:' not in html and 'http:' not in html
print('15 asset hashes/lengths verified; exact maintained guest only')
# The native allowlist must attest the same bytes, not just the JSON manifest.
swift=(root/'Sources/AssetCatalog.swift').read_text()
for item in manifest:
 assert f'VMAsset(name: "{item["name"]}", bytes: {item["bytes"]}, sha256: "{item["sha256"]}", mime: "{item["mime"]}")' in swift, item['name']
