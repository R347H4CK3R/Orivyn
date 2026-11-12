#!/usr/bin/env python3
"""Review regressions; actual tiny ZIP/XML inputs, plus library-produced interoperability files.
No Word, Excel or LibreOffice process is used or claimed. ZIP timestamps are normalized.
"""
from pathlib import Path
import io, json, struct, zipfile, hashlib, random, runpy, datetime, re
from xml.sax.saxutils import escape
ROOT=Path(__file__).resolve().parents[1]; FIX=ROOT/'Tests/OfficeFixtures'
base=runpy.run_path(str(ROOT/'scripts/generate_fixtures.py'))
package=base['package'];W,S,R,P=base['W'],base['S'],base['R'],base['P']
def write(name,files,stored=()):
 b=io.BytesIO()
 with zipfile.ZipFile(b,'w') as z:
  for path,content in files.items():
   zi=zipfile.ZipInfo(path,date_time=(2020,1,1,0,0,0));zi.create_system=3;zi.external_attr=0o100600<<16
   zi.compress_type=zipfile.ZIP_STORED if path in stored else zipfile.ZIP_DEFLATED
   z.writestr(zi,content.encode() if isinstance(content,str) else content)
 (FIX/name).write_bytes(b.getvalue())
def sheet(cells):return f'<worksheet xmlns="{S}"><sheetData>{cells}</sheetData></worksheet>'
def col(n):
 out=''
 while n:n,r=divmod(n-1,26);out=chr(65+r)+out
 return out
rng=random.Random(9371)
large=''.join(rng.choice('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789|\\') for _ in range(32768))
refs=''.join(f'<c r="{col(i)}1" t="s"><v>0</v></c>' for i in range(1,10001))
for name,value in [('repeated-large-shared.xlsx',large),('repeated-combining.xlsx','a'+'\u0301'*16383)]:
 files=package('xlsx',**{'xl/sharedStrings.xml':f'<sst xmlns="{S}"><si><t>{escape(value)}</t></si></sst>', 'xl/worksheets/sheet1.xml':sheet(f'<row r="1">{refs}</row>')})
 write(name,files,stored=('xl/sharedStrings.xml',))
combining='a'+'\u0301'*16383
write('combining.docx',package('docx',**{'word/document.xml':f'<w:document xmlns:w="{W}"><w:body><w:p><w:r><w:t>{combining}</w:t></w:r></w:p></w:body></w:document>'}),stored=('word/document.xml',))
(FIX/'combining.csv').write_text(combining+'\n',encoding='utf8')
for name,fmt in [('style-zero-date.xlsx',14),('style-zero-custom.xlsx',164)]:
 style=f'<styleSheet xmlns="{S}"><numFmts count="1"><numFmt numFmtId="164" formatCode="yyyy-mm-dd"/></numFmts><cellXfs count="1"><xf numFmtId="{fmt}"/></cellXfs></styleSheet>'
 write(name,package('xlsx',**{'xl/styles.xml':style,'xl/worksheets/sheet1.xml':sheet('<row r="1"><c r="A1"><v>60</v></c><c r="B1" s="0"><v>60</v></c></row>')}))
write('inherited-styles.xlsx',package('xlsx',**{'xl/worksheets/sheet1.xml':f'<worksheet xmlns="{S}"><cols><col min="1" max="1" style="1"/></cols><sheetData><row r="1" s="1" customFormat="1"><c r="A1"><v>60</v></c><c r="B1" s="1"><v>60</v></c></row></sheetData></worksheet>'}))
array=sheet('<row r="1"><c r="A1"><f t="array" ref="A1:A3">SUM(1,2)</f><v>3</v></c></row><row r="2"><c r="A2"><v>4</v></c></row><row r="3"><c r="A3"/></row>')
write('array-formula.xlsx',package('xlsx',**{'xl/worksheets/sheet1.xml':array}))
for name,reference in [('oversized-formula-range.xlsx','A1:XFD1048576'),('bad-formula-range.xlsx','A1:XFE1'),('formula-anchor-outside.xlsx','B1:B2')]:
 write(name,package('xlsx',**{'xl/worksheets/sheet1.xml':sheet(f'<row r="1"><c r="A1"><f t="array" ref="{reference}">1</f><v>1</v></c></row>')}))
many=''.join(f'<c r="{col(i)}1"><f t="array" ref="{col(i)}1">1</f><v>1</v></c>' for i in range(1,258))
write('too-many-formula-ranges.xlsx',package('xlsx',**{'xl/worksheets/sheet1.xml':sheet(f'<row r="1">{many}</row>')}))
bad_refs=refs.rsplit('<v>0</v>',1);bad_refs='<v>999</v>'.join(bad_refs)
write('invalid-after-cap.xlsx',package('xlsx',**{'xl/sharedStrings.xml':f'<sst xmlns="{S}"><si><t>{escape(large)}</t></si></sst>','xl/worksheets/sheet1.xml':sheet(f'<row r="1">{bad_refs}</row>')}),stored=('xl/sharedStrings.xml',))
(FIX/'invalid-after-cap.csv').write_text(('a'*1000)+',"unterminated\n',encoding='utf8')
# Each named boundary is isolated: inert file names, legal earlier metadata, distinct stages.
block=random.Random(1647).randbytes(4096)
files=package('docx');files['unused.dat']=block*1280;write('entry-size.docx',files)
files=package('docx')
for i in range(9):files[f'unused{i}.dat']=block*1024
write('total-size.docx',files)
files=package('docx');files['unused.dat']=b'A'*65536;write('bomb.docx',files)
# Nested LOCAL HEADER inside a stored outer payload. Both central records match their own
# local headers and sizes; only the final interval-overlap check rejects this archive.
inner_name=b'nested.dat';inner_data=b'inner fixture';inner_crc=__import__('zlib').crc32(inner_data)
inner=struct.pack('<IHHHHHIIIHH',0x04034b50,20,0,0,0,0,inner_crc,len(inner_data),len(inner_data),len(inner_name),0)+inner_name+inner_data
files=package('docx');files['outer.dat']=b'prefix'+inner+b'suffix';write('overlap.docx',files,stored=('outer.dat',))
data=(FIX/'overlap.docx').read_bytes()
with zipfile.ZipFile(io.BytesIO(data)) as z:info=z.getinfo('outer.dat')
local=info.header_offset;offset=local+30+len(info.filename.encode())+6
record=struct.pack('<IHHHHHHIIIHHHHHII',0x02014b50,0x314,20,0,0,0,0,inner_crc,len(inner_data),len(inner_data),len(inner_name),0,0,0,0,0o100600<<16,offset)+inner_name
end=len(data)-22;count,central_size,central_start=struct.unpack_from('<HII',data,end+10)
new_end=struct.pack('<IHHHHIIH',0x06054b50,0,0,count+1,count+1,central_size+len(record),central_start,0)
(FIX/'overlap.docx').write_bytes(data[:end]+record+new_end)
for name,decl in [('xml-declaration-spacing.docx','<?xml version = "1.0" encoding ="UTF-8"?>'),('xml-declaration-no-encoding.docx','<?xml version="1.0"?>'),('xml-declaration-misleading.docx','<?xml version="1.0" encoding="ISO-8859-1"?>')]:
 xml=decl+'<!-- unrelated encoding=\'utf-8\' -->'+f'<w:document xmlns:w="{W}"><w:body><w:p><w:r><w:t>encoding information</w:t></w:r></w:p></w:body></w:document>'
 write(name,package('docx',**{'word/document.xml':xml}))
data=bytearray((FIX/'paragraphs-tables.docx').read_bytes());end=len(data)-22;p=struct.unpack_from('<I',data,end+16)[0]
for _ in range(struct.unpack_from('<H',data,end+10)[0]):
 local=struct.unpack_from('<I',data,p+42)[0]
 for at in [p+8,local+6]:struct.pack_into('<H',data,at,struct.unpack_from('<H',data,at)[0]|2)
 n,e,c=struct.unpack_from('<HHH',data,p+28);p+=46+n+e+c
(FIX/'deflate-level-flags.docx').write_bytes(data)
files=package('docx');files['empty.dat']=b'';write('empty-deflate-part.docx',files)
files=package('docx');files['word/printerSettings/printerSettings1.bin']=b'opaque inert synthetic printer data';write('printer-settings.docx',files)
# Library-produced files. ZIP timestamp normalization leaves document XML exactly as emitted
# except deterministic core-property timestamps, which do not change document contents.
import docx, openpyxl, xlsxwriter
fixed=datetime.datetime(2020,1,1)
provenance={}
def normalize(name,raw,producer,version):
 out={}
 with zipfile.ZipFile(io.BytesIO(raw)) as z:
  for item in z.infolist():
   content=z.read(item)
   if item.filename=='docProps/core.xml':
    content=re.sub(rb'(<dcterms:(?:created|modified)[^>]*>)[^<]*(</dcterms:(?:created|modified)>)',rb'\g<1>2020-01-01T00:00:00Z\g<2>',content)
   out[item.filename]=content
 write(name,out)
 provenance[name]={'producer':producer,'version':version,'normalization':'ZIP metadata timestamps/permissions/compression normalized; core created/modified timestamps fixed to 2020-01-01. Other producer-emitted XML/parts unchanged.','native_office_application_used':False}
d=docx.Document();d.core_properties.created=fixed;d.core_properties.modified=fixed;d.add_paragraph('Library exported paragraph');table=d.add_table(rows=1,cols=2);table.cell(0,0).text='Fruit';table.cell(0,1).text='Kiwi';b=io.BytesIO();d.save(b);normalize('producer-python-docx.docx',b.getvalue(),'python-docx',docx.__version__)
w=openpyxl.Workbook();w.properties.created=fixed;w.properties.modified=fixed;w.active.title='Library sheet';w.active.append(['Value','Date']);w.active.append([42,datetime.datetime(2026,11,12)]);b=io.BytesIO();w.save(b);normalize('producer-openpyxl.xlsx',b.getvalue(),'openpyxl',openpyxl.__version__)
b=io.BytesIO();w=xlsxwriter.Workbook(b,{'in_memory':True});w.set_properties({'created':fixed});ws=w.add_worksheet('Library cache');ws.write('A1','Library exported spreadsheet');ws.write_formula('A2','=3+4',None,7);w.close();normalize('producer-xlsxwriter.xlsx',b.getvalue(),'XlsxWriter',xlsxwriter.__version__)
(ROOT/'provenance/fixture-producers.json').write_text(json.dumps(provenance,indent=2)+'\n')
manifest={p.name:{'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(FIX.iterdir()) if p.is_file() and p.name!='manifest.json'}
(FIX/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(f'Review fixtures complete: {len(manifest)} total files; library producer provenance saved.')
