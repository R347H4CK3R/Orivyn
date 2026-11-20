import pathlib, unittest
R=pathlib.Path(__file__).resolve().parents[2]
class PassageContract(unittest.TestCase):
    def test_uses_direct_verified_local_engine_under_owned_lease(self):
        app=(R/'JarvisEVO/UI/AppModel.swift').read_text()
        excerpt=app.split('func explainPassage(',1)[1].split('func revokeHeavyWork(',1)[0]
        for token in ('selectedLocalAgentProvider','beginHeavyWork','local.store.verifiedURL','local.engine.stream','revokeHeavyWork','resourceReleaser.unload','endHeavyWork'):
            self.assertIn(token,excerpt)
        for token in ('submit(', 'OpenRouter', 'automaticProviderFactory', 'memory', 'pendingAttachments'):
            self.assertNotIn(token,excerpt)
        self.assertLess(excerpt.index('local.store.verifiedURL'),excerpt.index('local.engine.stream'))
        self.assertLess(excerpt.index('resourceReleaser.unload'),excerpt.index('endHeavyWork'))
    def test_view_scoped_to_passage_and_cancels_on_exit(self):
        ui=(R/'JarvisEVO/UI/PassageExplanationView.swift').read_text()
        for token in ('TextEditor','Explain on this iPhone','.onDisappear','.onChange(of: scenePhase)','Source link supplied by you'):
            self.assertIn(token,ui)
        for token in ('UIPasteboard','URLSession','FreeOnline','@AppStorage','@SceneStorage'):
            self.assertNotIn(token,ui)
if __name__=='__main__': unittest.main()
