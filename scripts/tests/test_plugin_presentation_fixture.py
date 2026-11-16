import pathlib
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]

class PluginPresentationFixtureTests(unittest.TestCase):
    def test_debug_hook_uses_production_parser_binding_and_publisher(self):
        source = (ROOT / 'JarvisEVO/UI/AppModel.swift').read_text()
        hook = source[source.index('#if DEBUG\nextension AppModel {'):]
        self.assertIn('requestedMode == "plugin-suggestion"', hook)
        self.assertIn('let turn = normalChatTurnForDraft', hook)
        for token in ['ChatPluginProposalProvider(', 'validateChatPluginProposal(', 'publishChatPluginProposal(', 'preparedAssistant:', 'submit(text:']:
            self.assertIn(token, hook)
        self.assertNotIn('storedPluginProposal =', hook)
        self.assertNotIn('prepareReview(', hook)
        self.assertNotIn('.execute(', hook)
        fixture = (ROOT / 'JarvisEVO/UI/PluginProposalPresentationFixture.swift').read_text()
        self.assertTrue(fixture.startswith('#if DEBUG\n'))
        self.assertIn('calls += 1', fixture)
        self.assertNotIn('URLSession', fixture)
        native = (ROOT / 'UITests/ChatPluginSuggestionUITests.swift').read_text()
        self.assertNotIn('buttons["plugin.run"].tap()', native)
        self.assertIn('Checks: 2', native)

if __name__ == '__main__': unittest.main()
