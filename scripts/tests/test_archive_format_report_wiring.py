"""Source wiring checks only; native UI/service gates establish runtime behavior."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class ArchiveFormatReportWiringTests(unittest.TestCase):
    def test_report_is_explicit_read_only_and_cleared_with_selection(self):
        view = (ROOT/'JarvisEVO/UI/ArchiveRestoreView.swift').read_text()
        self.assertIn('archive.inspect-format', view)
        self.assertIn('archive.retained-format', view)
        self.assertIn('archive.format-summary', view)
        self.assertIn('Metadata presence is not format validation or an automatic attachment mapping.', view)
        self.assertIn('formatSummary = nil', view)
        method = view.split('private func inspectFormat(')[1].split('@MainActor private func')[0]
        self.assertIn('loadFormatReport(selected)', method)
        self.assertIn('guard active, lifetime.isValid, operationID == id', method)
        self.assertNotIn('commitAttachment', method)
        self.assertNotIn('ShareLink', method)
    def test_report_reuses_validated_service_off_main_actor(self):
        model = (ROOT/'JarvisEVO/UI/AppModel.swift').read_text()
        self.assertIn('func retainedArchiveFormatReport(', model)
        self.assertIn('ArchiveRestoreService.formatReport(review: review, jobsRoot: root)', model)
        settings = (ROOT/'JarvisEVO/UI/SettingsView.swift').read_text()
        self.assertIn('loadFormatReport: { review in try await model.retainedArchiveFormatReport(review) }', settings)
