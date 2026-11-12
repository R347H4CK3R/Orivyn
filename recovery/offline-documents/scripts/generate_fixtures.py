#!/usr/bin/env python3
"""Deterministic tiny synthetic Office packages. No third-party documents/data."""
if __name__ == '__main__':
    import runpy
    from pathlib import Path
    runpy.run_path(str(Path(__file__).with_name('generate_review_fixtures.py')),run_name='__main__')
    raise SystemExit(0)
import io, json, struct, zipfile, hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]/'Tests'/'OfficeFixtures'
ROOT.mkdir(parents=True,exist_ok=True)
W='http://schemas.openxmlformats.org/wordprocessingml/2006/main'
S='http://schemas.openxmlformats.org/spreadsheetml/2006/main'
R='http://schemas.openxmlformats.org/officeDocument/2006/relationships'
P='http://schemas.openxmlformats.org/package/2006/relationships'
C='http://schemas.openxmlformats.org/package/2006/content-types'
def package(kind, **replacements):
    main='word/document.xml' if kind=='docx' else 'xl/workbook.xml'
    mime='application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml' if kind=='docx' else 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml'
    files={'[Content_Types].xml':f'<Types xmlns="{C}"><Override PartName="/{main}" ContentType="{mime}"/></Types>',
      '_rels/.rels':f'<Relationships xmlns="{P}"><Relationship Id="rId1" Type="{R}/officeDocument" Target="{main}"/></Relationships>'}
    if kind=='docx':
      files[main]=f'<w:document xmlns:w="{W}"><w:body><w:p><w:r><w:t>Hello café</w:t></w:r><w:r><w:tab/><w:t>世界</w:t><w:br/><w:t>Next line</w:t></w:r></w:p><w:tbl><w:tr><w:tc><w:p><w:r><w:t>Fruit</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Count</w:t></w:r></w:p></w:tc></w:tr><w:tr><w:tc><w:p><w:r><w:t>Kiwi</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>4</w:t></w:r></w:p></w:tc></w:tr></w:tbl><w:p><w:del><w:r><w:delText>deleted secret</w:delText></w:r></w:del></w:p></w:body></w:document>'
    else:
      files.update({main:f'<workbook xmlns="{S}" xmlns:r="{R}"><workbookPr date1904="0"/><sheets><sheet name="Sales" sheetId="1" r:id="rId1"/><sheet name="Hidden sheet" sheetId="2" r:id="rId2" state="hidden"/></sheets></workbook>',
      'xl/_rels/workbook.xml.rels':f'<Relationships xmlns="{P}"><Relationship Id="rId1" Type="{R}/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="{R}/worksheet" Target="worksheets/sheet2.xml"/><Relationship Id="rId3" Type="{R}/sharedStrings" Target="sharedStrings.xml"/><Relationship Id="rId4" Type="{R}/styles" Target="styles.xml"/></Relationships>',
      'xl/sharedStrings.xml':f'<sst xmlns="{S}"><si><r><t>Total</t></r><r><t> revenue</t></r><rPh sb="0" eb="1"><t>phonetic ignored</t></rPh></si></sst>',
      'xl/styles.xml':f'<styleSheet xmlns="{S}"><cellXfs count="3"><xf numFmtId="0"/><xf numFmtId="14"/><xf numFmtId="164"/></cellXfs><numFmts count="1"><numFmt numFmtId="164" formatCode="yyyy-mm-dd"/></numFmts></styleSheet>',
      'xl/worksheets/sheet1.xml':f'<worksheet xmlns="{S}"><sheetData><row r="1"><c r="A1" t="s"><v>0</v></c><c r="C1" t="inlineStr"><is><t>USD</t></is></c></row><row r="2"><c r="A2"><v>42.50</v></c><c r="B2" t="b"><v>1</v></c><c r="C2" t="e"><v>#DIV/0!</v></c><c r="D2" t="d"><v>2026-11-12T00:00:00Z</v></c></row><row r="3"><c r="A3"><f>SUM(A2:A2)</f><v>42.50</v></c><c r="B3"><f>NOW()</f></c><c r="C3" s="1"><v>60</v></c><c r="D3" s="2"><v>45200</v></c></row></sheetData></worksheet>',
      'xl/worksheets/sheet2.xml':f'<worksheet xmlns="{S}"><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>Hidden data</t></is></c></row></sheetData></worksheet>'})
    files.update(replacements);return files

def write(name, files, extras=()):
    b=io.BytesIO()
    with zipfile.ZipFile(b,'w',compression=zipfile.ZIP_DEFLATED) as z:
      for p,s in list(files.items())+list(extras):
        zi=zipfile.ZipInfo(p, date_time=(2020,1,1,0,0,0));zi.compress_type=zipfile.ZIP_DEFLATED;zi.create_system=3;zi.external_attr=0o100600<<16
        z.writestr(zi,s.encode() if isinstance(s,str) else s)
    (ROOT/name).write_bytes(b.getvalue())
write('paragraphs-tables.docx',package('docx'))
write('types-and-formulas.xlsx',package('xlsx'))
write('empty.docx',package('docx',**{'word/document.xml':f'<w:document xmlns:w="{W}"><w:body><w:p/></w:body></w:document>'}))
write('duplicate.docx',package('docx'), [('word/document.xml','<bad/>')])
for name,path in [('traversal','../escape'),('absolute','/tmp/escape'),('backslash','word\\evil'),('percent','word/%2e%2e/evil')]:write(name+'.docx',package('docx'),[(path,'evil')])
write('case-collision.docx',package('docx'), [('Word/document.xml','<bad/>')])
write('entity.docx',package('docx',**{'word/document.xml':f'<!DOCTYPE document [<!ENTITY x SYSTEM "file:///etc/passwd">]><w:document xmlns:w="{W}"><w:body><w:p><w:r><w:t>&x;</w:t></w:r></w:p></w:body></w:document>'}))
write('depth.docx',package('docx',**{'word/document.xml':f'<w:document xmlns:w="{W}"><w:body>'+('<w:p>'*70)+('x')+('</w:p>'*70)+'</w:body></w:document>'}))
write('malformed-xml.docx',package('docx',**{'word/document.xml':'<w:document'}))
write('bomb.docx',package('docx'),[('unused.bin',b'a'*(5*1024*1024))])
write('macro.docx',package('docx'),[('word/vbaProject.bin',b'not code')])
write('relationship-traversal.xlsx',package('xlsx',**{'xl/_rels/workbook.xml.rels':f'<Relationships xmlns="{P}"><Relationship Id="rId1" Type="{R}/worksheet" Target="../../outside.xml"/></Relationships>'}))
write('external-worksheet.xlsx',package('xlsx',**{'xl/_rels/workbook.xml.rels':f'<Relationships xmlns="{P}"><Relationship Id="rId1" Type="{R}/worksheet" Target="https://example.invalid/sheet.xml" TargetMode="External"/></Relationships>'}))
write('duplicate-relationship.xlsx',package('xlsx',**{'xl/_rels/workbook.xml.rels':f'<Relationships xmlns="{P}"><Relationship Id="rId1" Type="{R}/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId1" Type="{R}/worksheet" Target="worksheets/sheet2.xml"/></Relationships>'}))
write('bad-shared-index.xlsx',package('xlsx',**{'xl/worksheets/sheet1.xml':f'<worksheet xmlns="{S}"><sheetData><row r="1"><c r="A1" t="s"><v>999</v></c></row></sheetData></worksheet>'}))
write('bad-coordinate.xlsx',package('xlsx',**{'xl/worksheets/sheet1.xml':f'<worksheet xmlns="{S}"><sheetData><row r="1"><c r="XFE1"><v>3</v></c></row></sheetData></worksheet>'}))
write('unknown-cell.xlsx',package('xlsx',**{'xl/worksheets/sheet1.xml':f'<worksheet xmlns="{S}"><sheetData><row r="1"><c r="A1" t="future"><v>3</v></c></row></sheetData></worksheet>'}))
write('date1904.xlsx',package('xlsx',**{'xl/workbook.xml':f'<workbook xmlns="{S}" xmlns:r="{R}"><workbookPr date1904="1"/><sheets><sheet name="Dates" sheetId="1" r:id="rId1"/></sheets></workbook>'}))
# Deliberate corruption stays tiny and deterministic.
base=(ROOT/'paragraphs-tables.docx').read_bytes()
for name,mutate in [('encrypted.docx',lambda b:None),('bad-crc.docx',lambda b:None),('symlink.docx',lambda b:None),('forged-small-size.docx',lambda b:None)]:
    b=bytearray(base); cd=b.index(b'PK\x01\x02'); local=struct.unpack_from('<I',b,cd+42)[0]
    if name=='encrypted.docx':
      for off in [local+6,cd+8]:struct.pack_into('<H',b,off,struct.unpack_from('<H',b,off)[0]|1)
    elif name=='bad-crc.docx':
      for off in [local+14,cd+16]:struct.pack_into('<I',b,off,0x12345678)
    elif name=='symlink.docx':struct.pack_into('<I',b,cd+38,0o120777<<16)
    else:
      for off in [local+22,cd+24]:struct.pack_into('<I',b,off,1)
    (ROOT/name).write_bytes(b)
(ROOT/'truncated.docx').write_bytes(base[:-5])
(ROOT/'structured.csv').write_text('name,value,note\r\nkiwi,4,"a,b"\r\n"café",5,"line one\nline two"\r\n"a""b",0,\r\n',encoding='utf8')
(ROOT/'structured.tsv').write_text('name\tvalue\nkiwi\t4\n',encoding='utf8')
(ROOT/'bad.csv').write_text('a,"unterminated\n',encoding='utf8')
# Additional compact malformed/compatibility packages.
write('bad-date.xlsx',package('xlsx',**{'xl/worksheets/sheet1.xml':f'<worksheet xmlns="{S}"><sheetData><row r="1"><c r="A1" t="d"><v>2026-02-30</v></c></row></sheetData></worksheet>'}))
write('nonfinite.xlsx',package('xlsx',**{'xl/worksheets/sheet1.xml':f'<worksheet xmlns="{S}"><sheetData><row r="1"><c r="A1"><v>NaN</v></c></row></sheetData></worksheet>'}))
write('duplicate-row.xlsx',package('xlsx',**{'xl/worksheets/sheet1.xml':f'<worksheet xmlns="{S}"><sheetData><row r="1"><c r="A1"><v>1</v></c></row><row r="1"><c r="A1"><v>2</v></c></row></sheetData></worksheet>'}))
write('namespace-spoof.xlsx',package('xlsx',**{'xl/workbook.xml':f'<workbook xmlns="{S}" xmlns:r="https://example.invalid/fake"><sheets><sheet name="Wrong relationship namespace" sheetId="1" r:id="rId1"/></sheets></workbook>'}))
write('namespace-alias.xlsx',package('xlsx',**{'xl/workbook.xml':f'<s:workbook xmlns:s="{S}" xmlns:rel="{R}"><s:sheets><s:sheet name="Alias" sheetId="1" rel:id="rId1"/></s:sheets></s:workbook>'}))
write('rooted-target.xlsx',package('xlsx',**{'_rels/.rels':f'<Relationships xmlns="{P}"><Relationship Id="rId1" Type="{R}/officeDocument" Target="/xl/workbook.xml"/></Relationships>'}))
write('utf16-xml.docx',package('docx',**{'word/document.xml':f'<?xml version="1.0" encoding="utf-16"?><w:document xmlns:w="{W}"><w:body/></w:document>'.encode('utf-16')}))
write('long-string.docx',package('docx',**{'word/document.xml':f'<w:document xmlns:w="{W}"><w:body><w:p><w:r><w:t>'+('abcde'*7000)+'</w:t></w:r></w:p></w:body></w:document>'}))
# Signed streaming descriptors are supported. Central/local disagreement is not.
class NonSeeking(io.BytesIO):
    def seekable(self):return False
    def seek(self,*args):raise io.UnsupportedOperation('fixture streaming writer')
b=NonSeeking()
with zipfile.ZipFile(b,'w',compression=zipfile.ZIP_DEFLATED) as z:
    for path,content in package('docx').items():
      zi=zipfile.ZipInfo(path,date_time=(2020,1,1,0,0,0));zi.compress_type=zipfile.ZIP_DEFLATED;zi.create_system=3;zi.external_attr=0o100600<<16;z.writestr(zi,content)
(ROOT/'signed-descriptors.docx').write_bytes(b.getvalue())
for name in ['header-mismatch.docx','overlap.docx','zip64.docx','unsupported-method.docx']:
    b=bytearray(base);cd=b.index(b'PK\x01\x02');local=struct.unpack_from('<I',b,cd+42)[0]
    if name=='header-mismatch.docx':struct.pack_into('<H',b,local+6,0x0800)
    elif name=='overlap.docx':
      second=cd+46+struct.unpack_from('<H',b,cd+28)[0]+struct.unpack_from('<H',b,cd+30)[0]+struct.unpack_from('<H',b,cd+32)[0]
      struct.pack_into('<I',b,second+42,0)
    elif name=='zip64.docx':struct.pack_into('<H',b,cd+6,45)
    else:
      struct.pack_into('<H',b,cd+10,99);struct.pack_into('<H',b,local+8,99)
    (ROOT/name).write_bytes(b)
(ROOT/'not-utf8.csv').write_bytes(b'field,\xff\xfe')
(ROOT/'quote-in-bare.csv').write_text('a,b"c\n',encoding='utf8')
(ROOT/'junk-after-quote.csv').write_text('a,"b"c\n',encoding='utf8')

write('escaped-strings.xlsx',package('xlsx',**{'xl/sharedStrings.xml':f'<sst xmlns="{S}"><si><t>line_x000D_break _x005F_x0041_ _xD83D__xDE00_</t></si></sst>'}))
write('invalid-surrogate.xlsx',package('xlsx',**{'xl/sharedStrings.xml':f'<sst xmlns="{S}"><si><t>bad_xD800_</t></si></sst>'}))
write('cache-types.xlsx',package('xlsx',**{'xl/worksheets/sheet1.xml':f'<worksheet xmlns="{S}"><sheetData><row r="1"><c r="A1" t="str"><f>IF(1,"","")</f><v/></c><c r="B1" t="s"><f>TEXT(1,"0")</f></c><c r="C1" t="b"><f>FALSE()</f><v>0</v></c><c r="D1" t="e"><f>1/0</f><v>#DIV/0!</v></c><c r="E1" t="d"><f>DATE(2026,11,12)</f><v>2026-11-12</v></c><c r="F1" t="b"><f>FALSE()</f><v/></c><c r="G1" t="d"><f>NOW()</f><v/></c></row></sheetData></worksheet>'}))
files=package('xlsx');files.pop('xl/styles.xml');files['xl/_rels/workbook.xml.rels']=files['xl/_rels/workbook.xml.rels'].replace(f'<Relationship Id="rId4" Type="{R}/styles" Target="styles.xml"/>','');files['xl/worksheets/sheet1.xml']=f'<worksheet xmlns="{S}"><sheetData><row r="1"><c r="A1" s="0"><v>1</v></c></row></sheetData></worksheet>';write('default-style.xlsx',files)

manifest={p.name:{'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(ROOT.iterdir()) if p.is_file() and p.name!='manifest.json'}
(ROOT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(f'Generated {len(manifest)} fixtures in {ROOT}')
