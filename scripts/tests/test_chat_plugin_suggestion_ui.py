"""UI source contracts only. Does not claim native rendering or tool execution."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ChatPluginSuggestionUITests(unittest.TestCase):
    def test_suggestion_is_app_metadata_and_requires_live_review_route(self):
        path = ROOT / 'JarvisEVO/UI/ChatPluginSuggestionView.swift'
        self.assertTrue(path.exists(), 'App-owned suggestion card is missing')
        source = path.read_text()
        self.assertIn('Suggested call · not executed', source)
        self.assertIn('model.pendingPluginProposal', source)
        self.assertIn('model.pluginProposalReviewRoute(id:', source)
        self.assertIn('PluginToolCallView(', source)
        self.assertIn('request: item.route.request', source)
        self.assertNotIn('PluginTaskProposalView(', source)
        self.assertNotIn('.execute(', source)
        self.assertNotIn('.prepareReview(', source)
        self.assertNotIn('.send()', source)
        self.assertNotIn('.onDisappear { presentation = nil }', source)
        self.assertIn('model.dismissPluginProposal(id:', source)
        self.assertIn('chat.pluginSuggestion.review', source)

    def test_opening_review_consumes_card_only_after_validation_and_serialization(self):
        source = (ROOT / 'JarvisEVO/UI/ChatPluginSuggestionView.swift').read_text()
        body = source[source.index('private func openReview'):]
        self.assertIn('model.dismissPluginProposal(id: route.id)', body)
        self.assertLess(body.index('model.pluginProposalReviewRoute(id:'), body.index('route.arguments.encoded'))
        self.assertLess(body.index('route.arguments.encoded'), body.index('model.dismissPluginProposal(id: route.id)'))
        self.assertLess(body.index('model.dismissPluginProposal(id: route.id)'), body.index('presentation = Presentation'))

    def test_card_is_embedded_and_invalidates_stale_presentation(self):
        path = ROOT / 'JarvisEVO/UI/ChatPluginSuggestionView.swift'
        self.assertTrue(path.exists())
        source = path.read_text()
        for context in ['pluginResultConversationContext', 'pluginProposalProviderContext',
                        'proposalCatalogID', 'activeConnection?.id']:
            self.assertIn('.onChange(of: model.' + ('plugins?.' if context in ['proposalCatalogID', 'activeConnection?.id'] else '') + context, source)
        self.assertIn('ChatPluginSuggestionView(model: model)', (ROOT / 'JarvisEVO/UI/RootView.swift').read_text())


if __name__ == '__main__':
    unittest.main()
