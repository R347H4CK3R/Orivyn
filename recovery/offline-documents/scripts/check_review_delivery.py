#!/usr/bin/env python3
"""Review-specific independent Python evidence. Does not execute Swift or native Office."""
from pathlib import Path
import hashlib, json, re, runpy, unittest, zipfile, io, datetime
R=Path(__file__).resolve().parents[1];F=R/'Tests/OfficeFixtures'
base=runpy.run_path(str(R/'scripts/check_office_delivery.py'))
metadata,stream_oracle,bounded_xml,Rejected=[base[k] for k in ['metadata','stream_oracle','bounded_xml','Rejected']]
def parts(name):
 d=(F/name).read_bytes();return stream_oracle(d,metadata(d))
S='{http://schemas.openxmlformats.org/spreadsheetml/2006/main}'
class ReviewChecks(unittest.TestCase):
 def test_stage_specific_adversarial_fixtures(self):
  expected={'entry-size.docx':'declaredEntryBytes','total-size.docx':'declaredTotalBytes','bomb.docx':'declaredExpansionRatio','overlap.docx':'archiveOverlap','forged-small-size.docx':'streamedDeclaredBytes','bad-crc.docx':'archiveIntegrity'}
  for name,stage in expected.items():
   with self.subTest(name=name),self.assertRaisesRegex(Rejected,'^'+stage+'$'):parts(name)
 def test_safe_deflate_and_printer_profiles_are_real(self):
  for name in ['deflate-level-flags.docx','empty-deflate-part.docx','printer-settings.docx']:
   p=parts(name);self.assertIn(b'Hello caf',p['word/document.xml'])
  d=(F/'empty-deflate-part.docx').read_bytes();m=metadata(d)['empty.dat'];self.assertGreater(m[1],0);self.assertEqual(m[2],0)
  with self.assertRaisesRegex(Rejected,'executable part'):parts('macro.docx')
 def test_repeated_string_fixture_reaches_document_layer_and_is_high_amplification(self):
  p=parts('repeated-large-shared.xlsx');shared=bounded_xml(p['xl/sharedStrings.xml']);sheet=bounded_xml(p['xl/worksheets/sheet1.xml'])
  value=shared.find('.//'+S+'t').text;cells=sheet.findall('.//'+S+'c')
  self.assertEqual(len(value.encode()),32768);self.assertEqual(len(cells),10000);self.assertEqual(len(value.encode())*len(cells),327680000)
  self.assertLess((F/'repeated-large-shared.xlsx').stat().st_size,100000)
 def test_combining_fixtures_are_not_zip_bombs_or_oversized_strings(self):
  for name,path in [('repeated-combining.xlsx','xl/sharedStrings.xml'),('combining.docx','word/document.xml')]:
   p=parts(name);bounded_xml(p[path])
  for name in ['repeated-combining.xlsx','combining.docx','combining.csv']:self.assertTrue((F/name).exists())
 def test_byte_sink_reference_charges_escapes_and_stops_without_repeated_value_copies(self):
  # Separate bounded oracle, not execution of the Swift sink. It retains no rendered rows.
  source='\n\t|\\'+('a'+'\u0301'*16383)
  out=bytearray();scalars=0;sealed=False
  for _ in range(10000):
   for scalar in source:
    token={'\n':'\\n','\t':'\\t','|':'\\|','\\':'\\\\'}.get(scalar,scalar)
    for c in token:
     b=c.encode()
     if scalars>=60000 or len(b)>97-len(out):sealed=True;break
     out.extend(b);scalars+=1
    if sealed:break
   if sealed:break
  self.assertTrue(sealed);self.assertLessEqual(len(out),97);out.decode('utf8');self.assertTrue(out.startswith(b'\\n\\t\\|\\\\'))
 def test_style_zero_and_inherited_style_metadata_is_real(self):
  for n,id in [('style-zero-date.xlsx','14'),('style-zero-custom.xlsx','164')]:
   p=parts(n);root=bounded_xml(p['xl/styles.xml']);self.assertEqual(root.find(S+'cellXfs')[0].get('numFmtId'),id)
   cells=bounded_xml(p['xl/worksheets/sheet1.xml']).findall('.//'+S+'c');self.assertIsNone(cells[0].get('s'));self.assertEqual(cells[1].get('s'),'0')
  p=parts('inherited-styles.xlsx');root=bounded_xml(p['xl/worksheets/sheet1.xml']);self.assertIsNotNone(root.find(S+'cols')[0].get('style'));self.assertEqual(root.find('.//'+S+'row').get('customFormat'),'1')
 def test_sparse_array_formula_and_malicious_ranges_are_real(self):
  root=bounded_xml(parts('array-formula.xlsx')['xl/worksheets/sheet1.xml']);cells=root.findall('.//'+S+'c')
  self.assertEqual(cells[0].find(S+'f').get('ref'),'A1:A3');self.assertIsNone(cells[1].find(S+'f'));self.assertEqual(cells[1].find(S+'v').text,'4');self.assertIsNone(cells[2].find(S+'v'))
  many=bounded_xml(parts('too-many-formula-ranges.xlsx')['xl/worksheets/sheet1.xml']).findall('.//'+S+'f');self.assertEqual(len(many),257)
  ref=bounded_xml(parts('oversized-formula-range.xlsx')['xl/worksheets/sheet1.xml']).find('.//'+S+'f').get('ref');self.assertEqual(ref,'A1:XFD1048576')
 def test_xml_declarations_are_tested_in_actual_parts(self):
  for n in ['xml-declaration-spacing.docx','xml-declaration-no-encoding.docx']:bounded_xml(parts(n)['word/document.xml'])
  with self.assertRaisesRegex(Rejected,'encoding'):bounded_xml(parts('xml-declaration-misleading.docx')['word/document.xml'])
 def test_library_export_provenance_and_readability(self):
  import docx,openpyxl
  self.assertIn('Library exported paragraph',' '.join(p.text for p in docx.Document(F/'producer-python-docx.docx').paragraphs))
  book=openpyxl.load_workbook(F/'producer-openpyxl.xlsx',data_only=True);self.assertEqual(book.active['A2'].value,42)
  cached=openpyxl.load_workbook(F/'producer-xlsxwriter.xlsx',data_only=True);self.assertEqual(cached.active['A2'].value,7)
  provenance=json.loads((R/'provenance/fixture-producers.json').read_text());self.assertEqual(len(provenance),3)
  for n,p in provenance.items():self.assertFalse(p['native_office_application_used']);parts(n)
 def test_source_has_no_full_row_or_full_value_rendering_and_uses_finite_ranges(self):
  extraction=(R/'JarvisEVO/Services/OfficeTextExtractor.swift').read_text();csv=(R/'JarvisEVO/Services/DelimitedDocumentReader.swift').read_text();sink=(R/'JarvisEVO/Services/OfflineDocumentReader.swift').read_text()
  rendering=extraction.split('    private func word(',1)[1].split('    private func collectFormulaRanges',1)[0]
  self.assertNotIn('parts.append(',rendering);self.assertNotIn('parts.joined(',rendering);self.assertNotIn('OfficeTextEscaping.render',extraction+csv)
  self.assertNotIn('row.enumerated().map',csv);self.assertIn('appendEscaped(value)',extraction)
  self.assertIn('scalar.utf8.count <= maximumBytes - byteCount',sink);self.assertIn('maximumOutputBytes = 240_000',sink)
  self.assertIn('maximumFormulaRanges = 256',sink);self.assertIn('maximumFormulaRangeCells = 1_000_000',sink);self.assertIn('maximumFormulaComparisons = 1_000_000',sink)
  self.assertIn('result.count < limits.maximumFormulaRanges',extraction);self.assertIn('formulaRanges.contains',extraction);self.assertIn('limits.maximumFormulaComparisons - formulaComparisons',extraction)
  self.assertIn('Int(styleText ?? "0")',extraction);self.assertIn('inherited number formats are unresolved',extraction)
 def test_cancellation_and_fifo_contracts_are_present(self):
  source='\n'.join(p.read_text() for p in (R/'JarvisEVO/Services').glob('*.swift'))
  self.assertIn('O_CLOEXEC | O_NONBLOCK',source);self.assertIn('try callback?(phase)',source);self.assertIn('try Task.checkCancellation()',source)
  tests='\n'.join(p.read_text() for p in (R/'Tests').glob('*.swift'))
  self.assertIn('withUnsafeCurrentTask { $0?.cancel() }',tests);self.assertIn('CancellationAfterStaging',tests);self.assertIn('XCTMemoryMetric()',tests)
  patch=(R/'proposed/office-integration.diff').read_text();self.assertIn('officeReader.checkpoint(.stagedOriginal)',patch);self.assertIn('officeReader: OfflineDocumentReader',patch)
 def test_before_manifest_stays_exact(self):
  before=R/'repair-round1/before';m=json.loads((R/'repair-round1/before-manifest.json').read_text())
  for name,a in m.items():d=(before/name).read_bytes();self.assertEqual(len(d),a['bytes']);self.assertEqual(hashlib.sha256(d).hexdigest(),a['sha256'])
  old=json.loads((before/'proposed/base-source-sha256.json').read_text());self.assertEqual(old,json.loads((R/'proposed/base-source-sha256.json').read_text()))

if __name__=='__main__':unittest.main(verbosity=2)
