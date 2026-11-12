from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class ExtendedNativeGateTests(unittest.TestCase):
    def test_full_candidate_seeds_actual_simulator_location(self):
        source = (ROOT / 'scripts/ci_macos.sh').read_text()
        self.assertTrue('xcrun simctl location "$SIMULATOR_ID" set 37.3349,-122.0090' in source,
                        'Full native gate must supply the same actual simulator location as the focused UI gate')

    def test_real_download_test_has_bounded_extended_allowance(self):
        source = (ROOT / 'UITests/AutomaticRealInferenceUITests.swift').read_text()
        self.assertTrue('executionTimeAllowance = 600' in source)
        self.assertTrue('-maximum-test-execution-time-allowance 720' in (ROOT / 'scripts/ci_macos.sh').read_text())
        self.assertTrue('-default-test-execution-time-allowance 120' in (ROOT / 'scripts/ci_macos.sh').read_text(),
                        'Do not extend every ordinary test to ten minutes')

if __name__ == '__main__': unittest.main()
