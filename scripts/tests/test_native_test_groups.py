import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("native_test_groups", ROOT / "scripts/native_test_groups.py")
groups = importlib.util.module_from_spec(spec)
spec.loader.exec_module(groups)


class NativeTestGroupsTests(unittest.TestCase):
    def test_ui_partition_covers_every_test_file_exactly_once(self):
        # Independent of the selector's class regex: all current UI suites use
        # one same-named XCTestCase per *UITests.swift file.
        expected = {path.stem for path in (ROOT / "UITests").rglob("*UITests.swift")}
        selected = [groups.selection(f"ui-{index}") for index in range(3)]
        actual = [item.split("/", 1)[1] for shard in selected for item in shard]
        self.assertEqual(set(actual), expected)
        self.assertEqual(len(actual), len(expected))
        self.assertEqual(sorted(actual), groups.ui_classes(ROOT / "UITests"))
        self.assertLessEqual(max(map(len, selected)) - min(map(len, selected)), 1)
        for index, shard in enumerate(selected):
            self.assertEqual(shard, [f"-only-testing:JarvisEVOUITests/{name}"
                                    for name in sorted(expected)[index::3]])

    def test_core_has_only_unit_target_and_all_preserves_unfiltered_run(self):
        self.assertEqual(groups.selection("core"), ["-only-testing:JarvisEVOTests"])
        self.assertEqual(groups.selection("all"), [])

    def test_unknown_group_rejected_before_ci_side_effects(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "scripts").mkdir()
            for name in ("ci_macos.sh", "native_test_groups.py"):
                shutil.copyfile(ROOT / "scripts" / name, root / "scripts" / name)
            import os
            environment = dict(os.environ, ORIVYN_NATIVE_TEST_GROUP="ui-3")
            result = subprocess.run(["bash", str(root / "scripts/ci_macos.sh")],
                                    env=environment, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Unknown native test group", result.stderr)
            self.assertFalse((root / "artifacts").exists())
            self.assertFalse((root / ".cache").exists())

    def test_unrecognized_or_duplicate_test_class_fails_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "NewTests.swift").write_text("class NewTests: CustomBase { func testExample() {} }")
            with self.assertRaises(ValueError): groups.ui_classes(root)
            (root / "NewTests.swift").write_text("class Same: XCTestCase {}")
            (root / "OtherTests.swift").write_text("class Same: XCTestCase {}")
            with self.assertRaises(ValueError): groups.ui_classes(root)

    def test_workflow_runs_all_groups_without_fail_fast(self):
        workflow = (ROOT / ".github/workflows/verify.yml").read_text()
        self.assertIn("group: [core, ui-0, ui-1, ui-2]", workflow)
        self.assertIn("fail-fast: false", workflow)
        self.assertIn("ORIVYN_NATIVE_TEST_GROUP: ${{ matrix.group }}", workflow)
        self.assertIn("name: Orivyn-native-capability-evidence-${{ matrix.group }}", workflow)
        script = (ROOT / "scripts/ci_macos.sh").read_text()
        self.assertIn('ORIVYN_NATIVE_TEST_GROUP:-all', script)
        self.assertLess(script.index('if [[ "$NATIVE_TEST_GROUP" == ui-* ]]'),
                        script.index('-configuration Release'))
        self.assertIn('exit 0', script[script.index('if [[ "$NATIVE_TEST_GROUP" == ui-* ]]'):script.index('-configuration Release')])


if __name__ == "__main__":
    unittest.main()
