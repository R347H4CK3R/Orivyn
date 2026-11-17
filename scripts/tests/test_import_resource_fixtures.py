import importlib.util,pathlib,tempfile,unittest,zipfile
ROOT=pathlib.Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('fixtures',ROOT/'scripts/make_import_resource_fixtures.py')
fixtures=importlib.util.module_from_spec(spec);spec.loader.exec_module(fixtures)
class ImportResourceFixturesTests(unittest.TestCase):
    def test_synthetic_dense_and_malformed_zip_shapes(self):
        with tempfile.TemporaryDirectory() as directory:
            root=pathlib.Path(directory);length=fixtures.generate(root)
            self.assertLess(length,16_000_000)
            self.assertGreater(length,15_000_000)
            with zipfile.ZipFile(root/'dense-metadata.zip') as archive:
                self.assertEqual(archive.namelist(),['conversations.json'])
                body=archive.read('conversations.json')
                self.assertEqual(body.count(b'"c":false'),279000)
                self.assertIn(b'Retained synthetic message',body)
            with zipfile.ZipFile(root/'malformed-metadata.zip') as archive:
                self.assertTrue(archive.read('conversations.json').endswith(b'[{},]}]'))
    def test_fixture_resources_are_only_in_test_target(self):
        project=(ROOT/'project.yml').read_text()
        before,test=project.split('  JarvisEVOTests:',1)
        self.assertNotIn('.cache/test-archives',before)
        self.assertIn('.cache/test-archives',test.split('  JarvisEVOUITests:')[0])

    def test_native_gate_runs_exact_resource_probes_and_new_tests(self):
        workflow=(ROOT/'.github/workflows/archive-restore.yml').read_text()
        self.assertIn('scripts/run_preservation_resource_probe.py',workflow)
        self.assertIn('scripts/run_import_resource_probe.py',workflow)
        self.assertIn('test "$PRESERVE" = 0 && test "$PARSE" = 0 && test "$EVIDENCE" = 0',workflow)
        gate=(ROOT/'scripts/ci_archive_restore.sh').read_text()
        for name in ['ArchiveReadBufferTests','ArchiveRestoreProgressTests','ArchiveRestoreResourceTests']:
            self.assertIn('-only-testing:JarvisEVOTests/'+name,gate)
        self.assertLess(gate.index('scripts/make_import_resource_fixtures.py'),gate.index('scripts/generate_project.py'))
