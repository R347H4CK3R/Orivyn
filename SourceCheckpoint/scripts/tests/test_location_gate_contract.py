"""Native acceptance must select the foreground location lifecycle suite."""
import pathlib
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]

class LocationGateContractTests(unittest.TestCase):
    def test_native_gate_selects_existing_location_lifecycle_suite(self):
        gate = (ROOT / 'scripts/run_virtual_desktop_gate.sh').read_text()
        self.assertIn('-only-testing:JarvisEVOTests/OneShotLocationTests', gate)
        self.assertTrue((ROOT / 'Tests/OneShotLocationTests.swift').is_file())
