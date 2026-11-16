from pathlib import Path
import plistlib
import unittest

ROOT = Path(__file__).resolve().parents[2]

class AssistantIdentityTests(unittest.TestCase):
    def test_assistant_name_is_jarvis_while_application_remains_orivyn(self):
        info = plistlib.loads((ROOT / 'JarvisEVO/Info.plist').read_bytes())
        self.assertEqual(info['CFBundleDisplayName'], 'Orivyn')
        source = (ROOT / 'JarvisEVO/Core/ChatResponsePolicy.swift').read_text()
        self.assertIn('ChatResponsePolicy.instructions', (ROOT / 'JarvisEVO/UI/AppModel.swift').read_text())
        self.assertTrue('You are Jarvis in Orivyn' in source, 'Missing requested Jarvis assistant identity')
        self.assertFalse('You are Orivyn, a helpful personal assistant.' in source, 'Obsolete assistant identity remains')

    def test_capability_copy_matches_real_tools_and_retains_limits(self):
        source = (ROOT / 'JarvisEVO/UI/SettingsView.swift').read_text()
        self.assertIn('local reminders', source)
        self.assertIn('Mail, Calendar, Safari and one-shot location', source)
        self.assertIn('Image Playground requires supported iOS 26 settings', source)
        self.assertIn('actual virtual desktop remain unfinished', source)
        self.assertNotIn('image generation, scheduled actions, external account integrations and cloud sync are not available', source)

    def test_actionable_help_does_not_pretend_tools_ran(self):
        source = (ROOT / 'JarvisEVO/Core/ChatResponsePolicy.swift').read_text()
        self.assertIn('ChatResponsePolicy.instructions', (ROOT / 'JarvisEVO/UI/AppModel.swift').read_text())
        self.assertTrue('do the useful part first' in source)
        self.assertTrue('offer the relevant reviewed tool screen' in source)
        self.assertTrue('without a recorded result' in source)
        self.assertTrue('Writing code as text is different from executing it' in source)

    def test_generated_image_storage_requests_complete_protection_without_downgrade(self):
        # Source contract only: Simulator cannot enforce the physical lock boundary.
        source = (ROOT / 'JarvisEVO/Services/GeneratedImageStaging.swift').read_text()
        self.assertIn('options: [.atomic, .completeFileProtection]', source)
        self.assertIn('.protectionKey: FileProtectionType.complete', source)
        self.assertNotIn('completeFileProtectionUntilFirstUserAuthentication', source)
        self.assertNotIn('FileProtectionType.none', source)

if __name__ == '__main__':
    unittest.main()
