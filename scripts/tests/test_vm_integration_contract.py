"""Packaging and source-order checks, NOT native behavior verification."""
from pathlib import Path
import unittest, hashlib, json, tempfile, importlib.util
ROOT = Path(__file__).resolve().parents[2]
class VMIntegrationContract(unittest.TestCase):
    def test_session_waits_for_preparation_and_runtime_before_releasing_lease(self):
        p=ROOT/'JarvisEVO/Core/VirtualDesktopSession.swift'
        self.assertTrue(p.exists(), 'Production virtual-desktop session missing')
        s=p.read_text()
        self.assertLess(s.index('await preparation?.value'), s.index('await runtime.stopAndWait()'))
        self.assertLess(s.index('await runtime.stopAndWait()'), s.index('model.endHeavyWork(id: id)',s.index('func close')))
        self.assertIn('if acknowledged',s)
        self.assertIn('model.revokeHeavyWork(id: id)',s)
    def test_assets_remain_folder_and_no_proof_app_entrypoint(self):
        p=ROOT/'JarvisEVO/Services/VirtualDesktop/VMHarness.swift'
        self.assertTrue(p.exists(), 'Production runtime adapter missing')
        s=p.read_text()
        self.assertNotIn('@main',s)
        self.assertIn('appendingPathComponent("VMAssets"',s)
        self.assertIn('type: folder',(ROOT/'project.yml').read_text())
    def test_bundled_guest_bytes_and_native_allowlist_agree(self):
        manifest=json.loads((ROOT/'docs/virtual-desktop/asset-manifest.json').read_text())
        self.assertEqual(len(manifest),15)
        native=(ROOT/'JarvisEVO/Services/VirtualDesktop/AssetCatalog.swift').read_text()
        # Clean checkouts intentionally omit the generated disk. Exercise the
        # production pinned materializer in temporary storage, never skip bytes.
        spec=importlib.util.spec_from_file_location('guest_materializer',ROOT/'scripts/materialize_guest.py')
        materializer=importlib.util.module_from_spec(spec);spec.loader.exec_module(materializer)
        with tempfile.TemporaryDirectory() as tmp:
            guest=Path(tmp)/'maintained.img'
            materializer.materialize(ROOT/'Fixtures/maintained.img.gz',guest)
            for entry in manifest:
                asset=ROOT/'JarvisEVO/Resources/VMAssets'/entry['name']
                if entry['name']=='maintained.img' and not asset.exists(): asset=guest
                self.assertEqual(asset.stat().st_size,entry['bytes'],entry['name'])
                with asset.open('rb') as stream:
                    self.assertEqual(hashlib.file_digest(stream,'sha256').hexdigest(),entry['sha256'],entry['name'])
                self.assertIn(entry['sha256'],native)
        html=(ROOT/'JarvisEVO/Resources/VMAssets/index.html').read_text()
        self.assertIn("default-src 'none'",html)
        self.assertIn("worker-src 'none'",html)
    def test_partial_start_without_webview_releases_asset_owner(self):
        s=(ROOT/'JarvisEVO/Services/VirtualDesktop/VMHarness.swift').read_text()
        self.assertIn('guard let old = webView else {\n            handler?.active = false; handler = nil',s)
if __name__=='__main__':unittest.main()
