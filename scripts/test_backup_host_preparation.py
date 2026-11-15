import hashlib
import json
import re
from pathlib import Path
import tempfile
import unittest
from prepare_backup_host_tests import prepare, TESTS, EXTRA_TESTS

ROOT=Path(__file__).resolve().parents[1]
class HostPreparationTests(unittest.TestCase):
    def test_exact_sources_and_existing_output_protected(self):
        with tempfile.TemporaryDirectory() as temp:
            output=Path(temp)/'proof'
            prepare(ROOT,output)
            entries=json.loads((output/'SOURCE-MANIFEST.json').read_text())
            self.assertEqual(len(entries),28)
            for entry in entries:
                source=Path(entry['source'])
                folder='Tests/JarvisEVOTests' if str(source).startswith('Tests/') else 'Sources/JarvisEVO'
                data=(output/folder/source.name).read_bytes()
                self.assertEqual(data,(ROOT/source).read_bytes())
                self.assertEqual(hashlib.sha256(data).hexdigest(),entry['sha256'])
            with self.assertRaises(FileExistsError): prepare(ROOT,output)
    def test_macos_sdk_sqlite_not_redeclared(self):
        with tempfile.TemporaryDirectory() as temp:
            output=Path(temp)/'proof'
            prepare(ROOT,output)
            package=(output/'Package.swift').read_text()
            self.assertFalse((output/'Sources/SQLite3').exists())
            self.assertNotIn('.systemLibrary',package)
            self.assertIn('.linkedLibrary("sqlite3")',package)
    def test_no_boot_or_run_claim(self):
        script=(ROOT/'scripts/ci_backup_without_boot.sh').read_text()
        commands='\n'.join(line for line in script.splitlines() if not line.startswith('#'))
        self.assertNotIn('simctl',commands)
        self.assertIn("generic/platform=iOS Simulator",commands)
        self.assertIn('build-for-testing',commands)
        self.assertIn('iOS tests NOT executed',commands)
        self.assertIn('Executed 152 tests, with 0 failures',commands)
    def test_darwin_count_accounts_for_linux_only_descriptor_test(self):
        total=0
        excluded=[]
        for name in TESTS+EXTRA_TESTS:
            linux=False
            for line in (ROOT/name).read_text().splitlines():
                stripped=line.strip()
                if stripped.startswith('#if'):
                    self.assertEqual(stripped, '#if os(Linux)', 'Review any new platform guard')
                    self.assertFalse(linux)
                    linux=True
                elif stripped.startswith('#endif'):
                    self.assertTrue(linux)
                    linux=False
                else:
                    self.assertFalse(stripped.startswith(('#else','#elseif')), 'Review branch conditions')
                    method=re.search(r'func (test\w+)\(', line)
                    if method:
                        if linux: excluded.append(method.group(1))
                        else: total+=1
            self.assertFalse(linux)
        self.assertEqual(excluded, ['testRepeatedInitializationMigrationFailureDoesNotLeakDatabaseDescriptors'])
        self.assertEqual(total,152)
        script=(ROOT/'scripts/ci_backup_without_boot.sh').read_text()
        self.assertIn('Executed 152 tests, with 0 failures',script)
        self.assertIn('Skipped checks are not allowed',script)
if __name__=='__main__': unittest.main()
