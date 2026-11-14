"""Executes production SQLite upsert SQL; Swift binding guard remains structural."""
from pathlib import Path
import re, sqlite3, unittest
ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'JarvisEVO/Persistence/SQLiteConversationStore.swift'
class PersistenceIntegrity(unittest.TestCase):
    def test_imported_memory_creation_index_matches_replacement_payload(self):
        source = SOURCE.read_text()
        sql = re.search(r'withStatement\("(INSERT INTO memory [^"\n]+)"', source).group(1)
        db = sqlite3.connect(':memory:')
        self.addCleanup(db.close)
        db.execute('CREATE TABLE memory(id TEXT PRIMARY KEY, content TEXT, created REAL, payload BLOB)')
        db.execute(sql, ('same', 'old', 10, b'old payload'))
        db.execute(sql, ('other', 'other', 20, b'other payload'))
        db.execute(sql, ('same', 'imported', 30, b'new payload'))
        self.assertEqual(db.execute('SELECT id,created,payload FROM memory ORDER BY created DESC').fetchone(), ('same',30,b'new payload'))
    def test_text_bind_does_not_use_nul_terminated_length(self):
        source = SOURCE.read_text()
        method = source[source.index('private func bind(_ value: String'):source.index('private func bind(_ value: Data')]
        self.assertNotIn('index, $0, -1, transient', method)
        self.assertIn('Int32(value.utf8.count)', method)
    def test_cleanup_failure_is_separate_from_committed_deletion(self):
        source = SOURCE.read_text()
        method = source[source.index('func deleteAll()'):source.index('func exportData()')]
        self.assertIn('throws -> String?', method)
        self.assertIn('return "Your conversations and memories were deleted', method)
        self.assertLess(method.index('throw error }'), method.index('PRAGMA wal_checkpoint'))
        model = (ROOT/'JarvisEVO/UI/AppModel.swift').read_text()
        self.assertIn('let maintenanceWarning = try await store.deleteAll()', model)
        self.assertIn('statusMessage = maintenanceWarning', model)
    def test_import_ui_discloses_matching_record_replacement(self):
        source = (ROOT/'JarvisEVO/UI/SettingsView.swift').read_text()
        self.assertIn('confirmingImport = true', source)
        self.assertIn('matching conversation and memory identifiers are replaced', source)
        self.assertIn('Button("Replace matching records…", role: .destructive)', source)
if __name__ == '__main__': unittest.main()
