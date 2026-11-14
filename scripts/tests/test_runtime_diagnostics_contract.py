"""Structural guards, not a substitute for native UI/state tests."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class RuntimeDiagnosticsContract(unittest.TestCase):
 def test_bounded_private_local_observation(self):
  core=ROOT/'JarvisEVO/Core/RuntimeDiagnostics.swift'
  self.assertTrue(core.is_file())
  s=core.read_text()
  self.assertIn('events.count > 200',s)
  self.assertIn('events.last?.state != state',s)
  ui=(ROOT/'JarvisEVO/UI/RuntimeDiagnosticsView.swift').read_text()
  self.assertIn('Task.sleep(for: .seconds(30))',ui)
  for forbidden in ['URLSession','remoteBaseURL','draft','message.content','apiKey','UserDefaults']:
   self.assertNotIn(forbidden,ui)
  self.assertIn('does not prove a stall',ui)
  self.assertIn('.task(id: scenePhase)',ui)
  self.assertIn('guard scenePhase == .active else',ui)
  model=(ROOT/'JarvisEVO/UI/AppModel.swift').read_text()
  self.assertIn('if downloadingModelID != nil, let progress = downloadProgress',model)
if __name__=='__main__':unittest.main()
