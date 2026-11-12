from pathlib import Path
import plistlib
import unittest

ROOT = Path(__file__).resolve().parents[2]

class AssistantIdentityTests(unittest.TestCase):
    def test_assistant_name_is_jarvis_while_application_remains_orivyn(self):
        info = plistlib.loads((ROOT / 'JarvisEVO/Info.plist').read_bytes())
        self.assertEqual(info['CFBundleDisplayName'], 'Orivyn')
        source = (ROOT / 'JarvisEVO/UI/AppModel.swift').read_text()
        self.assertTrue('You are Jarvis, the assistant in Orivyn.' in source, 'Missing requested Jarvis assistant identity')
        self.assertFalse('You are Orivyn, a helpful personal assistant.' in source, 'Obsolete assistant identity remains')

if __name__ == '__main__':
    unittest.main()
