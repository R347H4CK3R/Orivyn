import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("instrument", ROOT / "scripts/instrument_backup_picker.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class InstrumentationTests(unittest.TestCase):
    def test_candidate_preserves_guards_and_ui_assertions(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for rel in ["JarvisEVO/UI/SettingsView.swift", "UITests/JarvisEVOUITests.swift"]:
                dst = root / rel
                dst.parent.mkdir(parents=True, exist_ok=True)
                dst.write_text((ROOT / rel).read_text())
            original = (root / "UITests/JarvisEVOUITests.swift").read_text()
            module.instrument(root)
            test = (root / "UITests/JarvisEVOUITests.swift").read_text()
            start = original.index("    func testHistoryImportCancellation")
            self.assertIn(original[start:], test)
            source = (root / "JarvisEVO/UI/SettingsView.swift").read_text()
            self.assertIn("confirmation.invalidate()", source)
            self.assertIn("confirmation.finishSelection(selectionID)", source)
            self.assertIn("callback.stale", source)
            self.assertIn("#if DEBUG", source)
            self.assertNotIn("print(url", source)
            with self.assertRaises(AssertionError): module.instrument(root)

    def test_ci_is_pinned_bounded_and_keeps_failures(self):
        script = (ROOT / "scripts/ci_compare_backup_picker.sh").read_text()
        self.assertIn("--timeout 300", script)
        self.assertIn("run_variant baseline A1", script)
        self.assertIn("run_variant candidate B1", script)
        self.assertIn("run_variant candidate B2", script)
        self.assertIn("run_variant baseline A2", script)
        self.assertNotIn("simctl erase", script)
        self.assertNotIn("simctl shutdown", script)
        self.assertIn("s.get('totalTestCount')==1", script)
        workflow = (ROOT / ".github/workflows/backup-picker-comparison.yml").read_text()
        self.assertIn("github.event.repository.private == false", workflow)
        self.assertIn("timeout-minutes: 60", workflow)

    def test_both_variants_prepare_pinned_model_before_build(self):
        script = (ROOT / "scripts/ci_compare_backup_picker.sh").read_text()
        loop = script[script.index("for variant in baseline candidate;"):script.index("done")]
        self.assertIn("python3 scripts/download_test_model.py", loop)
        self.assertLess(loop.index("python3 scripts/download_test_model.py"), loop.index("python3 scripts/generate_project.py"))
        self.assertIn('cmp "$BASE/.cache/test-models/qwen2.5-0.5b-instruct-q4_k_m.gguf"', script)

    def test_zero_test_summary_is_infrastructure_not_app_failure(self):
        script = (ROOT / "scripts/ci_compare_backup_picker.sh").read_text()
        start = script.index("import json,sys,pathlib")
        end = script.index("\nPY", start)
        harness = script[start:end]
        import json, subprocess, sys
        for count, passed, failed, code, expected in [(0,0,0,65,"infrastructure"),(1,1,0,0,"pass"),(1,0,1,65,"fail")]:
            with self.subTest(count=count, passed=passed), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                (root / "summary.json").write_text(json.dumps(dict(totalTestCount=count, passedTests=passed, failedTests=failed, skippedTests=0)))
                (root / "exit.txt").write_text(str(code))
                subprocess.run([sys.executable, "-c", harness, temp], check=True, capture_output=True)
                self.assertEqual((root / "verdict.txt").read_text().strip(), expected)
