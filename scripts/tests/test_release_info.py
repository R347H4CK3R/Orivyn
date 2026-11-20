import pathlib, plistlib, unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
class ReleaseInfoTests(unittest.TestCase):
 def test_settings_exposes_bundle_build_and_release_notes(self):
  text=(ROOT/'JarvisEVO/UI/SettingsView.swift').read_text()
  self.assertIn('CFBundleVersion',text)
  self.assertIn('OrivynReleaseNotes',text)
  self.assertNotIn('?? "1.0"',text)
 def test_release_metadata_matches_requested_candidate(self):
  info=plistlib.loads((ROOT/'JarvisEVO/Info.plist').read_bytes())
  self.assertEqual(info['CFBundleShortVersionString'],'0.1.8')
  self.assertEqual(info['CFBundleVersion'],'24')
  self.assertIn('SideStore',info['OrivynReleaseNotes'])
