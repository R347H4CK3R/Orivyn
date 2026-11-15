"""Catalog generator contracts: publisher evidence, safe output and stable pins."""
import copy, importlib.util, json, pathlib, subprocess, sys, tempfile, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'scripts/model_catalog.py'

def fixture():
    return {'defaultModelID': 'tiny-q4_k_m', 'models': [{'id': 'tiny-q4_k_m', 'name': 'Tiny · Q4_K_M', 'baseModel': 'Tiny', 'family': 'Qwen', 'purpose': 'General chat', 'quantization': 'Q4_K_M', 'recommendedRAMGB': 4, 'notes': 'Short tasks.', 'repository': 'Qwen/Tiny-GGUF', 'revision': 'a' * 40, 'fileName': 'tiny-q4_k_m.gguf', 'sha256': 'b' * 64, 'byteCount': 100000000, 'license': 'Apache-2.0', 'licensePath': 'LICENSE', 'licenseSHA256': 'c' * 64, 'publisherLicense': 'apache-2.0', 'gated': False, 'architecture': 'qwen2'}]}

def evidence():
    return {'sources': [{'repository': 'Qwen/Tiny-GGUF', 'revision': 'a' * 40, 'publisherLicense': 'apache-2.0', 'gated': False, 'licenseURL': 'https://huggingface.co/Qwen/Tiny-GGUF/resolve/' + 'a' * 40 + '/LICENSE', 'licenseSHA256': 'c' * 64, 'files': [{'fileName': 'tiny-q4_k_m.gguf', 'byteCount': 100000000, 'sha256': 'b' * 64}]}]}

def templates():
    return [{'repository': 'Qwen/Tiny-GGUF', 'revision': 'a' * 40, 'file': 'tiny-q4_k_m.gguf', 'architecture': 'qwen2', 'renderedBytes': 10, 'templateSHA256': 'd' * 64}]

class CatalogTests(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.module = None
        if SCRIPT.exists():
            spec = importlib.util.spec_from_file_location('model_catalog', SCRIPT)
            cls.module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(cls.module)

    def renderer(self):
        self.assertIsNotNone(self.module, 'Catalog generator is not implemented')
        return self.module.render

    def test_generates_exact_pinned_artifact(self):
        s = self.renderer()(fixture(), evidence(), templates())
        self.assertIn('sha256: "' + 'b' * 64 + '"', s)
        self.assertIn('byteCount: 100000000', s)
        self.assertIn('https://huggingface.co/Qwen/Tiny-GGUF/resolve/' + 'a' * 40 + '/tiny-q4_k_m.gguf', s)

    def test_rejects_unsafe_inputs_and_unreviewed_license(self):
        render = self.renderer()
        bad = {'repository': 'someone/Tiny', 'revision': 'main', 'fileName': '../x.gguf', 'license': 'other', 'publisherLicense': 'other', 'gated': True, 'byteCount': 2000000001, 'recommendedRAMGB': 0}
        for key, value in bad.items():
            d = fixture()
            d['models'][0][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                render(d, evidence(), templates())

    def test_valid_looking_pins_must_match_independent_evidence(self):
        render = self.renderer()
        for key, value in {'revision': 'd' * 40, 'sha256': 'd' * 64, 'byteCount': 200000000, 'licenseSHA256': 'd' * 64, 'architecture': 'llama'}.items():
            d = fixture()
            d['models'][0][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                render(d, evidence(), templates())
        with self.assertRaises(ValueError):
            render(fixture(), evidence(), [])

    def test_duplicates_and_missing_default_fail(self):
        render = self.renderer()
        for change in ['id', 'fileName', 'default']:
            d = fixture()
            if change == 'default':
                d['defaultModelID'] = 'absent'
            else:
                m = copy.deepcopy(d['models'][0])
                m['id'] = 'other' if change == 'fileName' else m['id']
                m['fileName'] = 'other.gguf' if change == 'id' else m['fileName']
                d['models'].append(m)
            with self.subTest(change=change), self.assertRaises(ValueError):
                render(d, evidence(), templates())

    def test_swift_strings_escape_quotes_backslash_and_control_bytes(self):
        d = fixture()
        d['models'][0]['notes'] = '"quote" \\n\n' + chr(0) + chr(8) + chr(12)
        s = self.renderer()(d, evidence(), templates())
        self.assertIn('\\"quote\\" \\\\n\\n\\u{0}\\u{8}\\u{c}', s)

    def test_check_mode_never_rewrites_stale_output(self):
        self.renderer()
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            output = root / 'catalog.swift'
            output.write_text('stale')
            for name, data in [('catalog', fixture()), ('evidence', evidence()), ('templates', templates())]:
                (root / (name + '.json')).write_text(json.dumps(data))
            args = [sys.executable, str(SCRIPT), '--catalog', str(root / 'catalog.json'), '--evidence', str(root / 'evidence.json'), '--templates', str(root / 'templates.json'), '--output', str(output)]
            self.assertEqual(subprocess.run(args + ['--check'], capture_output=True).returncode, 1)
            self.assertEqual(output.read_text(), 'stale')
            self.assertEqual(subprocess.run(args, capture_output=True).returncode, 0)
            self.assertEqual(subprocess.run(args + ['--check'], capture_output=True).returncode, 0)

    def test_only_exact_reviewed_community_repository_is_allowed(self):
        for repository, accepted in [('ggml-org/Qwen3-1.7B-GGUF', True), ('ggml-org/Unreviewed-GGUF', False)]:
            d, e, t = fixture(), evidence(), templates()
            d['models'][0]['repository'] = repository
            e['sources'][0]['repository'] = repository
            e['sources'][0]['licenseURL'] = 'https://huggingface.co/' + repository + '/resolve/' + 'a' * 40 + '/LICENSE'
            t[0]['repository'] = repository
            if accepted:
                self.assertIn(repository, self.renderer()(d, e, t))
            else:
                with self.assertRaises(ValueError): self.renderer()(d, e, t)

    def test_shipped_catalog_is_valid_and_generated_output_current(self):
        self.renderer()
        p = subprocess.run([sys.executable, str(SCRIPT), '--check'], capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, p.stderr)
