#!/usr/bin/env python3
"""Propose only. Never writes to the frozen app tree."""
from pathlib import Path
import difflib, json, hashlib
ROOT=Path(__file__).resolve().parents[1]
BASE=Path('/workspace/shared/Jarvis-EVO-recovery-next')
patch=[]; references={}
def propose(path, edit):
    before=(BASE/path).read_text();after=edit(before)
    assert before!=after,path
    references[path]=hashlib.sha256(before.encode()).hexdigest()
    patch.extend(difflib.unified_diff(before.splitlines(True),after.splitlines(True),fromfile='a/'+path,tofile='b/'+path))
def attachment(s):
    s=s.replace('        let isPDF = type?.conforms(to: .pdf) == true','''        let officeFormat = OfflineDocumentFormat(filenameExtension: source.pathExtension)
        // Old binary/macro formats are not plain text, even if a provider reports a broad text type.
        guard !["doc", "xls", "docm", "xlsm", "xlsb"].contains(source.pathExtension.lowercased()) else { throw AttachmentError.unsupportedType }
        let isPDF = type?.conforms(to: .pdf) == true''')
    s=s.replace('guard isPDF || isText else','guard isPDF || isText || officeFormat != nil else')
    s=s.replace('let filename = id.uuidString + (isPDF ? ".pdf" : ".txt")','let filename = id.uuidString + (officeFormat.map { "." + $0.rawValue } ?? (isPDF ? ".pdf" : ".txt"))')
    s=s.replace('''        try FileManager.default.copyItem(at: source, to: destination)
        do {''','''        do {
            if officeFormat != nil {
                // Keep the exact bounded immutable snapshot as the private original. No second
                // source read can swap content between size checking, staging and extraction.
                let snapshot = try OfflineDocumentReader().boundedSnapshot(at: source)
                try snapshot.write(to: destination, options: .atomic)
            } else {
                try FileManager.default.copyItem(at: source, to: destination)
            }''')
    s=s.replace('''            if isPDF {
                guard let document''','''            if let officeFormat {
                let snapshot = try OfflineDocumentReader().boundedSnapshot(at: destination)
                extracted = try OfflineDocumentReader().read(data: snapshot, format: officeFormat).modelContext
            } else if isPDF {
                guard let document''')
    s=s.replace('mediaType: isPDF ? "application/pdf" : "text/plain"','mediaType: officeFormat?.mediaType ?? (isPDF ? "application/pdf" : "text/plain")')
    s=s.replace('Choose a PDF, UTF-8 text file, or JPEG, PNG, HEIC, or HEIF image. Images provide recognized text only to current models.','Choose a PDF, DOCX, XLSX, UTF-8 text, CSV, TSV, or JPEG, PNG, HEIC, or HEIF image. Office files provide bounded text and cached values, not exact layout or executed formulas. Images provide recognized text only to current models.')
    return s
def picker(s):
    s=s.replace('''        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf, .plainText, .json, .sourceCode, .jpeg, .png, .heic, .heif], asCopy: false)''','''        let officeTypes = ["docx", "xlsx", "csv", "tsv"].compactMap { UTType(filenameExtension: $0) }
        let types: [UTType] = [.pdf, .plainText, .json, .sourceCode, .jpeg, .png, .heic, .heif] + officeTypes
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)''')
    return s
def project(s):
    s=s.replace('packages:\n','''packages:
  ZIPFoundation:
    url: https://github.com/weichsel/ZIPFoundation.git
    revision: 22787ffb59de99e5dc1fbfe80b19c97a904ad48d
''',1)
    s=s.replace('''      - sdk: libsqlite3.tbd''','''      - package: ZIPFoundation
        product: ZIPFoundation
      - sdk: libsqlite3.tbd''',1)
    s=s.replace('''      - path: Tests
''','''      - path: Tests
        excludes: [OfficeFixtures]
      - path: Tests/OfficeFixtures
        type: folder
        buildPhase: resources
''',1)
    return s
propose('JarvisEVO/Services/AttachmentService.swift',attachment)
propose('JarvisEVO/UI/AttachmentViews.swift',picker)
propose('project.yml',project)
(ROOT/'proposed/office-integration.diff').write_text(''.join(patch))
(ROOT/'proposed/base-source-sha256.json').write_text(json.dumps(references,indent=2)+'\n')
print('Wrote proposed patch only; frozen app tree unchanged.')
