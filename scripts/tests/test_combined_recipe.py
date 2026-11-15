import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class CombinedRecipeTests(unittest.TestCase):
    def test_generator_matches_tracked_builder(self):
        path = ROOT / "Diagnostics/CombinedRuntime/prepare_build.py"
        spec = importlib.util.spec_from_file_location("combined_recipe", path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        generated = module.transform((ROOT / "Diagnostics/VisionRuntime/source/build-xcframework.sh").read_text())
        self.assertEqual(generated, (ROOT / "Diagnostics/CombinedRuntime/build-ios-combined.sh").read_text())
        self.assertNotIn("xcrun xcodebuild -version 2>/dev/null | head", generated)

if __name__ == "__main__":
    unittest.main()
