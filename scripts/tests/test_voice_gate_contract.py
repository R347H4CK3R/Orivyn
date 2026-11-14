"""Release-gate selector coverage only, not execution of native audio tests."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class VoiceGateContract(unittest.TestCase):
    def test_manual_native_gate_includes_voice_boundaries(self):
        gate = (ROOT / 'scripts/run_virtual_desktop_gate.sh').read_text()
        for name in ['VoiceServiceTests', 'VoiceConversationControllerTests', 'VoiceConversationSessionTests', 'VoiceAppModelTests']:
            self.assertTrue((ROOT / 'Tests' / (name + '.swift')).is_file())
            self.assertIn('-only-testing:JarvisEVOTests/' + name, gate)
        self.assertIn('-only-testing:JarvisEVOUITests/RootViewOwnershipUITests', gate)
    def test_idle_audio_events_require_prior_activity_before_notifying(self):
        source = (ROOT / 'JarvisEVO/Services/VoiceService.swift').read_text()
        for name, following in [('handleMediaServicesReset', 'handleInterruption'), ('handleInterruption', 'startRecording')]:
            section = source[source.index('private func ' + name + '('):source.index('func ' + following + '(')]
            self.assertIn('let wasActive = isRecording || isStarting || isFinishing || isSpeaking', section)
            self.assertIn('if wasActive { onInterruption?() }', section)
            self.assertLess(section.index('let wasActive'), section.index('stopRecording()'))
if __name__ == '__main__': unittest.main()
