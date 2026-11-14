"""Native acceptance must select the external-display disclosure state tests."""
import pathlib
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]

class DesktopGateContractTests(unittest.TestCase):
    def test_native_gate_selects_existing_display_state_suite(self):
        gate = (ROOT / 'scripts/run_virtual_desktop_gate.sh').read_text()
        self.assertIn('-only-testing:JarvisEVOTests/ExternalWorkspaceTests', gate)
        self.assertTrue((ROOT / 'Tests/ExternalWorkspaceTests.swift').is_file())
