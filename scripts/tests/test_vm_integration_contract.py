"""Packaging and source-order checks, NOT native behavior verification."""
from pathlib import Path
import unittest, hashlib, json
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
        for entry in manifest:
            data=(ROOT/'JarvisEVO/Resources/VMAssets'/entry['name']).read_bytes()
            self.assertEqual(len(data),entry['bytes'],entry['name'])
            self.assertEqual(hashlib.sha256(data).hexdigest(),entry['sha256'],entry['name'])
            self.assertIn(entry['sha256'],native)
        html=(ROOT/'JarvisEVO/Resources/VMAssets/index.html').read_text()
        self.assertIn("default-src 'none'",html)
        self.assertIn("worker-src 'none'",html)
    def test_partial_start_without_webview_releases_asset_owner(self):
        s=(ROOT/'JarvisEVO/Services/VirtualDesktop/VMHarness.swift').read_text()
        self.assertIn('guard let old = webView else {\n            handler?.active = false; handler = nil',s)
if __name__=='__main__':unittest.main()
