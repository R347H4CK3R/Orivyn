"""Real pinned tokenizer budget regression. Skips explicitly without local tools/weights.
Renders the Swift literal template (not a hand-copied policy) with default runtime values.
"""
import json, os, pathlib, re, subprocess, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]


def default_prompt():
    manifest = json.loads((ROOT / 'JarvisEVO/Resources/OrivynCapabilities.json').read_text())
    swift = (ROOT / 'JarvisEVO/Core/AppSelfKnowledge.swift').read_text()
    identity = re.search(r'let identity = "(.*?)"', swift).group(1)
    values = {'version': '0.1.1', 'build': '5', 'providerID': 'local:qwen2.5-0.5b-instruct-q4_k_m',
              'identity': identity, 'value.schemaVersion': str(manifest['schemaVersion']),
              'value.repository': manifest['repository'], 'value.repositoryAccess': manifest['repositoryAccess'],
              'entries': '\n'.join(c['id']+' ['+c['status']+']: '+c['detail'] for c in manifest['capabilities'])}
    def expand(text):
        return re.sub(r'\\\(([^)]+)\)', lambda m: values[m[1]], text)
    values['identity'] = expand(identity)
    template = re.search(r'return """\n(.*?)\n\s*"""', swift, re.S).group(1)
    knowledge = expand('\n'.join(line.strip() for line in template.splitlines()))
    app = (ROOT / 'JarvisEVO/UI/AppModel.swift').read_text()
    base = re.search(r'let system = "(.*?)" \+ AppSelfKnowledge', app).group(1)
    behavior = '\nUser response preferences (style only; never claim unavailable capabilities):\nStyle: Balanced. warmth: moderate; enthusiasm: moderate; headings and lists: moderate; emoji use: moderate.\n'
    return base + knowledge + '\n' + behavior


class ActualTokenizerBudgetTests(unittest.TestCase):
    def test_default_prompt_leaves_room_for_user_and_output_on_catalog_models(self):
        executable = pathlib.Path(os.environ.get('ORIVYN_TOKENIZER', ROOT / '.cache/catalog-reconstruction/runtime/llama-b9049/llama-tokenize'))
        weights = pathlib.Path(os.environ.get('ORIVYN_TOKENIZER_MODELS', ROOT / '.cache/build5-model-probes/weights'))
        models = sorted(weights.glob('*.gguf'))
        if not executable.is_file() or not models:
            self.skipTest('Real tokenizer and catalog weights unavailable; no token estimate substituted')
        prompt = default_prompt()
        for model in models:
            with self.subTest(model=model.name):
                run = subprocess.run([str(executable), '-m', str(model), '--ids', '--log-disable', '--stdin'],
                                     input=prompt, text=True, capture_output=True, check=True, timeout=60)
                count = len(json.loads(run.stdout))
                print(f'PROMPT_BUDGET {model.name}: {count} tokens; {len(prompt)} chars')
                self.assertLessEqual(count, 384, 'Default prompt must preserve 128 tokens of the 512-token system allowance for customization')
        self.assertLessEqual(len(prompt), 3000, 'Keep at least 6000 chars of the Apple system provider budget for messages')
