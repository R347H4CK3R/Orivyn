import importlib.util
import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("generate_project", ROOT / "scripts/generate_project.py")
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)

class ProjectGenerationTests(unittest.TestCase):
    def test_default_and_shipping_features_use_lean_graph(self):
        for flags in ("", "ORIVYN_NATIVE_VISION ORIVYN_NATIVE_TOOLS", "NOT_ORIVYN_PEER_TLS_SPIKE"):
            self.assertEqual(generator.selected_spec(flags), "project.yml")

    def test_exact_peer_token_and_explicit_gate_include_overlay(self):
        for flags in ("ORIVYN_PEER_TLS_SPIKE", "ORIVYN_NATIVE_TOOLS\tORIVYN_PEER_TLS_SPIKE\nORIVYN_NATIVE_VISION"):
            self.assertEqual(generator.selected_spec(flags), "project-peer.json")
        self.assertEqual(generator.selected_spec("", peer=True), "project-peer.json")

    def test_generator_runs_at_repository_root_and_propagates_failure(self):
        with patch.object(generator.subprocess, "run") as run:
            self.assertEqual(generator.generate("", peer=True), "project-peer.json")
            run.assert_called_once_with(["xcodegen", "generate", "--spec", "project-peer.json"], cwd=generator.ROOT, check=True)
            run.side_effect = subprocess.CalledProcessError(7, "xcodegen")
            with self.assertRaises(subprocess.CalledProcessError):
                generator.generate("")

    def test_overlay_preserves_pins_and_adds_only_peer_dependencies(self):
        overlay = json.loads((ROOT / "project-peer.json").read_text())
        self.assertEqual(overlay["include"], ["project.yml"])
        self.assertEqual({k:v["revision"] for k,v in overlay["packages"].items()}, {
            "PeerCertificates": "8789d7e78f996d56272836c8bf3590c5bd9c9754",
            "PeerASN1": "12b0abc19498e562a8d97eebb67a11e9e6a255dd",
            "PeerCrypto": "9f96b82711cc4ce5816343c02eccd5ad907972d3"})
        self.assertEqual(overlay["targets"], {"JarvisEVO": {"dependencies": [
            {"package": "PeerCertificates", "product": "X509"},
            {"package": "PeerASN1", "product": "SwiftASN1"}]}})
        base = (ROOT / "project.yml").read_text()
        for name in overlay["packages"]:
            self.assertNotIn(name, base)
        self.assertIn("package: LlamaRuntime", base)
        self.assertIn("sdk: libsqlite3.tbd", base)
        self.assertIn("sdk: JavaScriptCore.framework", base)

if __name__ == "__main__":
    unittest.main()
