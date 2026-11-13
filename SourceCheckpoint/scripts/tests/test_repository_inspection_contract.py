"""Structural guardrails only, not execution of native code or GitHub authentication."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class RepositoryInspectionContract(unittest.TestCase):
    def test_fixed_read_only_transport_and_verified_blob(self):
        source = (ROOT/'JarvisEVO/Core/RepositoryInspection.swift').read_text()
        self.assertIn('static let repository = "R347H4CK3R/Orivyn"', source)
        self.assertIn('request.httpMethod = "GET"', source)
        self.assertNotIn('httpMethod = "POST"', source)
        self.assertIn('guard response.url == url', source)
        self.assertIn('guard hash == entry.blobSHA', source)
        self.assertIn('func clearCredentials()', source)
        self.assertNotIn('SecItemAdd', source)
    def test_explicit_screen_clear_and_no_model_submission(self):
        source = (ROOT/'JarvisEVO/UI/RepositoryInspectionView.swift').read_text()
        self.assertIn('SecureField(', source)
        self.assertIn('.onDisappear { disconnect() }', source)
        self.assertIn('if value != .active { disconnect() }', source)
        self.assertNotIn('GenerationRequest', source)
        self.assertNotIn('save(', source)
        self.assertIn('not confirmed bugs', source)
    def test_source_preview_verifies_original_and_has_no_write_transport(self):
        source = (ROOT/'JarvisEVO/Services/SourceRepairDraftCore.swift').read_text()
        self.assertIn('guard hash == file.blobSHA',source)
        self.assertIn('draft.status == "draftNotApplied"',source)
        self.assertNotIn('URLRequest',source)
        self.assertNotIn('write(to:',source)
        view = (ROOT/'JarvisEVO/UI/SourceRepairDraftView.swift').read_text()
        self.assertIn('not applied or tested',view)
        self.assertIn('.onChange(of: replacement)',view)
        inspector = (ROOT/'JarvisEVO/UI/RepositoryInspectionView.swift').read_text()
        self.assertIn('.sheet(item: $repairSelection)',inspector)
        self.assertNotIn('NavigationLink("Prepare a local change preview")',inspector)
if __name__ == '__main__': unittest.main()
