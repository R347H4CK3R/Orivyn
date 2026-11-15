import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("runtime", ROOT / "scripts/select_reviewed_runtime.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class RuntimeTests(unittest.TestCase):
    def test_multiple_runtimes_choose_exact_validated_runtime(self):
        devices = {f"com.apple.CoreSimulator.SimRuntime.iOS-26-{v}": [{"name": "iPhone 16 Plus", "isAvailable": True, "udid": f"00000000-0000-0000-0000-00000000000{v}"}] for v in [0, 1, 2]}
        self.assertEqual(module.select({"devices": devices}), "00000000-0000-0000-0000-000000000001")

    def test_missing_ambiguous_unavailable_or_alias_fail_closed(self):
        device = {"name": "iPhone 16 Plus", "isAvailable": True, "udid": "00000000-0000-0000-0000-000000000001"}
        for values in [[], [device, device], [dict(device, isAvailable=False)], [dict(device, udid="all")]]:
            with self.subTest(values=values), self.assertRaises(ValueError):
                module.select({"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-26-1": values}})
