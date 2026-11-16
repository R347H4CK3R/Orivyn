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

    def test_revision_controls_are_debug_only_and_use_real_transitions(self):
        view = (ROOT / 'JarvisEVO/UI/ChatPluginSuggestionView.swift').read_text()
        block = view[view.index('#if DEBUG\n                        .toolbar'):].split('#endif', 1)[0]
        self.assertIn('requestedMode == "plugin-suggestion"', block)
        self.assertIn('fixtureActions.change(kind)', block)
        fixture = (ROOT / 'JarvisEVO/UI/RootViewRegressionFixtures.swift').read_text()
        self.assertIn('broker.review != nil', fixture)
        self.assertIn('broker.journal.records.isEmpty', fixture)
        self.assertIn('model.selectConversation(historyB); model.selectConversation(historyA)', fixture)
        self.assertIn('model.replaceProviders([ProviderOption(id: "replacement-ui-fixture"', fixture)
        self.assertIn('broker.disconnect()', fixture)
        self.assertIn('broker.proposalCatalogID != catalog', fixture)
        self.assertNotIn('Task.sleep', fixture[fixture.index('func changePluginRevision'):fixture.index('private var pluginClient')])

if __name__ == '__main__': unittest.main()
