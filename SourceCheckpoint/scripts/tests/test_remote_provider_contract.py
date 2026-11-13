"""Source-contract checks only; Swift streaming behavior needs the native gate."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class RemoteProviderContract(unittest.TestCase):
    def test_finish_reason_is_decoded_and_validated_before_token_return(self):
        source = (ROOT / 'JarvisEVO/Providers/OpenAICompatibleProvider.swift').read_text()
        self.assertIn('let finish_reason: String?', source)
        self.assertIn('if let reason = choice.finish_reason, reason != "stop"', source)
        for reason in ['length', 'content_filter', 'tool_calls', 'function_call']:
            self.assertIn('"' + reason + '"', source)
        self.assertLess(source.index('if let reason = choice.finish_reason'), source.index('return .token(content)'))
    def test_terminal_and_unsupported_delta_guards(self):
        source = (ROOT / 'JarvisEVO/Providers/OpenAICompatibleProvider.swift').read_text()
        self.assertIn('guard receivedStop else', source)
        self.assertIn('guard !receivedDone else', source)
        self.assertIn('guard !receivedStop || choice.finish_reason == nil else', source)
        self.assertIn('choice.delta?.refusal == nil', source)
    def test_native_gate_covers_remote_parser(self):
        self.assertIn('-only-testing:JarvisEVOTests/ProviderTests', (ROOT/'scripts/run_virtual_desktop_gate.sh').read_text())
if __name__ == '__main__': unittest.main()
