from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class DiscoveryUIHarnessTests(unittest.TestCase):
    def test_exact_single_test_and_strict_result(self):
        script=(ROOT/'scripts/ci_reviewed_discovery_ui.sh').read_text()
        self.assertEqual(script.count('-only-testing:'),1)
        self.assertIn('LocalAgentIntegrationUITests/testSavedTaskSurvivesRelaunchWithoutAutomaticExecution',script)
        for marker in ['materialize_guest.py','download_test_model.py','generate_project.py','select_reviewed_runtime.py','--timeout 300','verify_simulator_result.py','test "$status" -eq 0']:
            self.assertIn(marker,script)
        self.assertNotIn('simctl erase',script)
        self.assertNotIn('|| true',script)
    def test_workflow_read_only_bounded_and_three_features(self):
        s=(ROOT/'.github/workflows/reviewed-plan-discovery-ui.yml').read_text()
        for text in ['contents: read','private == false','runs-on: macos-15','timeout-minutes: 90','ORIVYN_NATIVE_VISION ORIVYN_NATIVE_TOOLS ORIVYN_NATIVE_TRANSCRIPT','persist-credentials: false','if: always()']:
            self.assertIn(text,s)
    def test_native_assertions_cover_hidden_and_recommended_paths(self):
        s=(ROOT/'UITests/LocalAgentIntegrationUITests.swift').read_text()
        self.assertIn('XCTAssertEqual(draft.label, "Draft plan for review")',s)
        self.assertLess(s.index('XCTAssertFalse(app.buttons["agent.create"].isHittable)'),s.index('experimental.tap()'))
        self.assertIn('Resume is explicit',s)
        self.assertIn('no approved completion checklist',s)
