"""Release-gate configuration checks, not execution of Xcode or an iPhone model."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class NativeInferenceRequirementTests(unittest.TestCase):
    def test_manual_acceptance_gate_cannot_silently_skip_model_inference(self):
        source = (ROOT / 'scripts/run_virtual_desktop_gate.sh').read_text()
        command = source[source.index('xcodebuild -project'):]
        self.assertIn('-only-testing:JarvisEVOTests/LocalInferenceTests', command)
        self.assertIn('JARVIS_REQUIRE_REAL_INFERENCE=1', command)
    def test_required_flag_reaches_test_process_and_missing_weights_fail(self):
        project = (ROOT / 'project.yml').read_text()
        test = (ROOT / 'Tests/LocalInferenceTests.swift').read_text()
        self.assertIn('JARVIS_REQUIRE_REAL_INFERENCE: $(JARVIS_REQUIRE_REAL_INFERENCE)', project)
        self.assertIn('environment["JARVIS_REQUIRE_REAL_INFERENCE"] == "1"', test)
        self.assertIn('XCTFail("Real inference was required', test)
if __name__ == '__main__': unittest.main()
