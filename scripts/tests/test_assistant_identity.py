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

    def test_capability_copy_matches_real_tools_and_retains_limits(self):
        source = (ROOT / 'JarvisEVO/UI/SettingsView.swift').read_text()
        self.assertIn('local reminders', source)
        self.assertIn('Mail, Calendar, Safari and one-shot location', source)
        self.assertIn('Image Playground requires supported iOS 26 settings', source)
        self.assertIn('actual virtual desktop remain unfinished', source)
        self.assertNotIn('image generation, scheduled actions, external account integrations and cloud sync are not available', source)

    def test_actionable_help_does_not_pretend_tools_ran(self):
        source = (ROOT / 'JarvisEVO/UI/AppModel.swift').read_text()
        self.assertTrue('Do the useful parts of the request first' in source)
        self.assertTrue('review in the real Email, Calendar, Browser, Location or Reminder screen' in source)
        self.assertTrue('Opening a review does not send, save or execute it' in source)
        self.assertTrue('Do not claim to browse, run code' in source)

if __name__ == '__main__':
    unittest.main()
