"""Structural native file-provider safeguards; actual native reader tests are separate."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class BackupReaderContract(unittest.TestCase):
 def test_bounded_coordinated_cancellable_reader(self):
  path=ROOT/'JarvisEVO/Services/BackupFileReader.swift'
  self.assertTrue(path.is_file())
  s=path.read_text()
  for guard in ['NSFileCoordinator','read(upToCount:', 'maximumBytes - data.count + 1','withTaskCancellationHandler','task.cancel()', 'Task.checkCancellation()', 'stopAccessingSecurityScopedResource', 'O_NOFOLLOW', 'O_NONBLOCK', 'fstat(descriptor, &attributes)' ]:
   self.assertIn(guard,s)
  self.assertNotIn('Data(contentsOf:',s)
 def test_history_uses_reader_without_main_actor_bulk_read(self):
  s=(ROOT/'JarvisEVO/UI/AppModel.swift').read_text()
  method=s[s.index('func importHistory('):s.index('func saveMemory(')]
  self.assertIn('try await BackupFileReader.read(url)',method)
  self.assertNotIn('Data(contentsOf:',method)
if __name__=='__main__':unittest.main()
