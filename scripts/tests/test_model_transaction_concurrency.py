"""Darwin Swift 6 must not retain a non-Sendable FileManager in static storage."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]

class ModelTransactionConcurrencyTests(unittest.TestCase):
    def test_file_manager_is_created_per_access_not_shared_static_storage(self):
        source = (ROOT / 'JarvisEVO/Providers/Local/ModelInstallTransaction.swift').read_text()
        self.assertNotRegex(source, r'static\s+let\s+fm\s*=')
        self.assertRegex(source, r'private static var fm: FileManager\s*\{\s*FileManager\(\)\s*\}')
        self.assertNotIn('nonisolated(unsafe)', source)
        self.assertNotIn('@unchecked Sendable', source)

if __name__ == '__main__':
    unittest.main()
