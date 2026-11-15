import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
PATH = ROOT / 'JarvisEVO/Resources/OrivynCapabilities.json'

class SelfKnowledgeManifestTests(unittest.TestCase):
    def manifest(self):
        self.assertTrue(PATH.is_file(), 'Versioned self-knowledge manifest is missing')
        return json.loads(PATH.read_text())

    def test_manifest_is_bounded_and_versioned(self):
        m = self.manifest()
        self.assertEqual(m['schemaVersion'], 1)
        self.assertLess(PATH.stat().st_size, 12000)
        self.assertEqual(m['repository'], 'https://github.com/R347H4CK3R/Orivyn')
        self.assertEqual(len({c['id'] for c in m['capabilities']}), len(m['capabilities']))
        for c in m['capabilities']:
            self.assertIn(c['status'], ['available', 'conditional', 'notAvailable'])
            self.assertTrue(c['detail'].strip())

    def test_unverified_vision_vm_and_self_repair_are_not_available(self):
        capabilities = {c['id']: c for c in self.manifest()['capabilities']}
        for key in ['visual-understanding', 'virtual-machine', 'self-repair']:
            self.assertEqual(capabilities[key]['status'], 'notAvailable')
        self.assertIn('visibility is not checked', self.manifest()['repositoryAccess'])
        self.assertIn('not source code', self.manifest()['repositoryAccess'])

    def test_repository_access_describes_boundary_not_stale_visibility(self):
        tools = (ROOT / 'JarvisEVO/Services/LocalReadTools.swift').read_text()
        prompt = (ROOT / 'JarvisEVO/Core/AppSelfKnowledge.swift').read_text()
        self.assertNotIn('Private. This tool', tools)
        self.assertIn('This tool reads bundled metadata, not repository source', tools)
        self.assertNotIn('(private).', prompt)
        self.assertIn('visibility is not checked', prompt)
        self.assertNotIn('repository is private', self.manifest()['repositoryAccess'])
