"""Source contract only; native rendering and AppModel eligibility are separate tests."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class LocalReadDisclosureTests(unittest.TestCase):
    def test_caption_uses_model_eligibility_and_exact_local_scope(self):
        source = (ROOT / 'JarvisEVO/UI/RootView.swift').read_text()
        match = re.search(r'if model\.automaticLocalChatReadsAvailable \{([^}]+)\}', source)
        self.assertIsNotNone(match, 'Local-read scope must be visible under the model eligibility guard')
        body = match.group(1)
        self.assertIn('On-device assistant may read saved memories, app info and installed models, and calculate explicit arithmetic. Receipts appear in chat.', body)
        self.assertIn('.accessibilityIdentifier("composer.localReads.notice")', body)
        self.assertEqual(source.count('composer.localReads.notice'), 1)
        self.assertNotIn('Button(', body, 'This is scope disclosure, not a second execution/consent control')

    def test_direct_execution_claim_uses_dispatcher_origin_gate(self):
        source = (ROOT / 'JarvisEVO/UI/RootView.swift').read_text()
        match = re.search(r'if model\.currentDirectLocalReadContract != nil \{([^}]+)\}', source)
        self.assertIsNotNone(match, 'No-model claim must share the dispatcher origin eligibility')
        self.assertIn('composer.localTask.routeNotice', match.group(1))
        self.assertIn('Send performs this read locally without contacting a model.', match.group(1))
        self.assertNotIn('private var chatChecklistRequest:', source)
        self.assertIn('reviewingLocalTask = request', source, 'Manual nonexecuting review must remain available')


if __name__ == '__main__':
    unittest.main()
