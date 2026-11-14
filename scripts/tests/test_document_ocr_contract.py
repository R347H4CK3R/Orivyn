"""Structural OCR/provenance checks, not native Apple Vision/PDFKit execution."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class DocumentOCRContract(unittest.TestCase):
 def test_image_ocr_preserves_real_scores_without_claiming_probability(self):
  service=(ROOT/'JarvisEVO/Services/ImageAttachmentService.swift').read_text()
  self.assertIn('confidence: primary.confidence',service)
  self.assertIn('topCandidates(2)',service)
  self.assertIn('.bounded(observations: observations)',service)
  evidence=(ROOT/'JarvisEVO/Core/OCRLineEvidence.swift').read_text()
  self.assertIn('not a correctness probability',evidence)
  self.assertIn('not a correction',evidence)
 def test_pdf_ocr_is_bounded_and_import_uses_real_extractor(self):
  source=(ROOT/'JarvisEVO/Services/PDFTextExtractor.swift').read_text()
  for text in ['maximumPages = 500','maximumOCRPages = 20','maximumRenderDimension = 1_600','maximumCharacters = 60_000','Task.checkCancellation()']:
   self.assertIn(text,source)
  self.assertIn('OCR-skipped pages',source)
  self.assertIn('does not prove a page is blank',source)
  importer=(ROOT/'JarvisEVO/Services/AttachmentService.swift').read_text()
  self.assertIn('try PDFTextExtractor.extract(document: document)',importer)
if __name__=='__main__':unittest.main()
