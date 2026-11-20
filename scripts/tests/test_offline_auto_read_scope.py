"""Structural guard only; native dispatch/fixtures require XCTest separately."""
import pathlib, unittest
class OfflineAutoReadScope(unittest.TestCase):
    def test_installed_decision_cannot_enter_normal_chat_read_runner(self):
        source = (pathlib.Path(__file__).resolve().parents[2] / "JarvisEVO/UI/AppModel.swift").read_text()
        preparation = source.split("private func prepareAutomaticSend(")[1].split("private func ownsAutomatic(")[0]
        self.assertIn("if installedDecision == nil, let local = provider as? LocalAIProvider", preparation)
        self.assertIn("self.submit(text: self.draft, attachments: self.pendingAttachments", preparation)
