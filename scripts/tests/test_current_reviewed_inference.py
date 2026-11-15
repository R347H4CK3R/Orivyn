from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class CurrentReviewedInferenceTests(unittest.TestCase):
    def test_single_existing_real_model_gate_and_preparation(self):
        text = (ROOT / 'scripts/ci_current_reviewed_inference.sh').read_text()
        for required in ['materialize_guest.py', 'bootstrap_llama.sh', 'download_test_model.py', 'generate_project.py', 'select_reviewed_runtime.py', '--timeout 300', 'ORIVYN_REQUIRE_NATIVE_TRANSCRIPT_ROUTE=1', 'NATIVE_TOOLS_GATE_KIND=reviewed-plan', 'ORIVYN_PRODUCTION_MODEL_ID=qwen3-1.7b-q4_k_m']:
            self.assertIn(required, text)
        self.assertEqual(text.count('bash Diagnostics/NativeTools/run_production_simulator.sh'), 1)
        self.assertLess(text.index('generate_project.py'), text.index('run_production_simulator.sh'))
        self.assertNotIn('simctl erase', text)
        self.assertNotIn('|| true', text)
    def test_workflow_is_bounded_read_only_not_publishing(self):
        text = (ROOT / '.github/workflows/current-reviewed-inference.yml').read_text()
        for required in ['contents: read', 'private == false', 'runs-on: macos-15', 'timeout-minutes: 90', 'persist-credentials: false', '/Applications/Xcode_26.1.app', 'if: always()']:
            self.assertIn(required, text)
        self.assertNotIn('contents: write', text)
        self.assertNotIn('publish-', text)
    def test_existing_gate_keeps_strict_result_verification(self):
        text = (ROOT / 'Diagnostics/NativeTools/run_production_simulator.sh').read_text()
        self.assertIn('verify_simulator_result.py', text)
        self.assertIn('testRequiredModelProposalApprovalAndGroundedRead', text)
