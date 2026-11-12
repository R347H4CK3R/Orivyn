#!/usr/bin/env python3
"""Independent Python fixture/contract checks. DOES NOT execute/compile the Swift reader.

The ZIP oracle uses stdlib zlib (not production Swift code) to check that synthetic
malicious fixtures actually exercise metadata, streamed-size and CRC boundaries.
"""
from pathlib import Path
import csv, hashlib, io, json, re, struct, unittest, zlib
import xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1]; FIX=ROOT/'Tests/OfficeFixtures'
class Rejected(ValueError):pass

def metadata(data):
    if not 22<=len(data)<=10*1024*1024:raise Rejected('input bytes')
    def u16(p):
      if not 0<=p<=len(data)-2:raise Rejected('u16 bounds')
      return struct.unpack_from('<H',data,p)[0]
    def u32(p):
      if not 0<=p<=len(data)-4:raise Rejected('u32 bounds')
      return struct.unpack_from('<I',data,p)[0]
    end=next((p for p in range(len(data)-22,max(-1,len(data)-65558),-1) if u32(p)==0x06054b50 and p+22+u16(p+20)==len(data)),None)
    if end is None:raise Rejected('eocd')
    count,size,start=u16(end+10),u32(end+12),u32(end+16)
    if u16(end+4) or u16(end+6) or u16(end+8)!=count or not 0<count<=512 or start+size!=end:raise Rejected('central directory')
    p=start; result={}; folded=set(); ranges=[]; total=0
    def extra(p,n):
      stop=p+n
      if stop>len(data):raise Rejected('extra bounds')
      while p<stop:
        tag,n=u16(p),u16(p+2)
        if p+4+n>stop or tag in [1,0x9901,0x7075]:raise Rejected('extra')
        p+=4+n
      if p!=stop:raise Rejected('extra end')
    for _ in range(count):
      if p>end-46 or u32(p)!=0x02014b50:raise Rejected('central signature')
      made,version,flags,method=u16(p+4),u16(p+6),u16(p+8),u16(p+10)
      crc,compressed,expanded=u32(p+16),u32(p+20),u32(p+24)
      n,e,c,disk=u16(p+28),u16(p+30),u16(p+32),u16(p+34)
      attr,local=u32(p+38),u32(p+42)
      if version>20 or flags & ~0x0808 or method not in [0,8] or disk or not 0<n<=255 or p+46+n+e+c>end:raise Rejected('unsupported ZIP profile')
      raw=data[p+46:p+46+n]
      if not all(32<=b<127 for b in raw):raise Rejected('name encoding')
      name=raw.decode();parts=name.removesuffix('/').split('/');directory=name.endswith('/')
      if name.startswith('/') or any(ch in name for ch in '\\:%?#') or any(c in ['', '.', '..'] for c in parts) or name.lower() in folded:raise Rejected('unsafe name')
      folded.add(name.lower());mode=(attr>>16)&0xf000
      if ((made>>8) in [3,19] and mode not in [0,0x4000 if directory else 0x8000]) or (attr&0x10 and not directory):raise Rejected('link/type')
      lower=name.lower()
      if lower.endswith('.bin') or any(x in lower for x in ['/embeddings/','/activex/','vbaproject','macrosheets/']):raise Rejected('executable part')
      if expanded>4*1024*1024 or total+expanded>32*1024*1024 or expanded>max(1,compressed)*200 or compressed>len(data) or (method==0 and expanded!=compressed) or (expanded==0 and compressed!=0) or (directory and (compressed or expanded or method or crc)):raise Rejected('declared resource bound')
      total+=expanded;extra(p+46+n,e)
      if local>start-30 or u32(local)!=0x04034b50 or u16(local+4)!=version or u16(local+6)!=flags or u16(local+8)!=method or u16(local+26)!=n:raise Rejected('local mismatch')
      le=u16(local+28);content=local+30+n+le
      if content>start-compressed or data[local+30:local+30+n]!=raw:raise Rejected('local bounds/name')
      extra(local+30+n,le);finish=content+compressed
      if flags&8:
        if u32(local+14) not in [0,crc] or u32(local+18) not in [0,compressed] or u32(local+22) not in [0,expanded] or finish>start-16 or [u32(finish+i) for i in [0,4,8,12]] != [0x08074b50,crc,compressed,expanded]:raise Rejected('descriptor')
        finish+=16
      elif [u32(local+i) for i in [14,18,22]] != [crc,compressed,expanded]:raise Rejected('sizes/CRC header disagreement')
      ranges.append((local,finish));result[name]=(content,compressed,expanded,crc,method);p+=46+n+e+c
    if p!=end:raise Rejected('central end')
    cursor=0
    for a,b in sorted(ranges):
      if a!=cursor or b<=cursor:raise Rejected('overlap or gap')
      cursor=b
    if cursor!=start:raise Rejected('local end')
    return result

def stream_oracle(data, entries):
    result={};total=0
    for name,(offset,compressed,expanded,crc,method) in entries.items():
      payload=data[offset:offset+compressed];actual=0;checksum=0;chunks=[]
      def consume(chunk):
        nonlocal actual,total,checksum
        if len(chunk)>min(4*1024*1024-actual,32*1024*1024-total,expanded-actual):raise Rejected('actual streamed bytes')
        actual+=len(chunk);total+=len(chunk);checksum=zlib.crc32(chunk,checksum)
        if name.endswith(('.xml','.rels')):chunks.append(chunk)
      if method==0:
        for p in range(0,len(payload),16384):consume(payload[p:p+16384])
      else:
        decoder=zlib.decompressobj(-15);pending=payload
        for _ in range(1300):
          chunk=decoder.decompress(pending,16384);consume(chunk);pending=decoder.unconsumed_tail
          if decoder.eof:break
          if not pending and not chunk:raise Rejected('no decoder progress')
        else:raise Rejected('callback bound')
        if not decoder.eof:raise Rejected('deflate end')
      if actual!=expanded or checksum!=crc:raise Rejected('actual bytes/CRC')
      result[name]=b''.join(chunks)
    return result

def bounded_xml(data):
    try:text=data.decode('utf8')
    except UnicodeError as e:raise Rejected('encoding') from e
    if '\0' in text or '<!DOCTYPE' in text.upper() or '<!ENTITY' in text.upper():raise Rejected('entities/encoding')
    try:root=ET.fromstring(data)
    except ET.ParseError as e:raise Rejected('XML grammar') from e
    nodes=0;textbytes=0
    def walk(node,depth):
      nonlocal nodes,textbytes
      nodes+=1
      if depth>64 or nodes>80000 or len(node.attrib)>32:raise Rejected('XML structural limit')
      for s in [node.text or '',node.tail or '']:
        textbytes+=len(s.encode())
        if len(s.encode())>32768 or textbytes>2*1024*1024:raise Rejected('XML text limit')
      for child in node:walk(child,depth+1)
    walk(root,1);return root

class FixtureChecks(unittest.TestCase):
    def test_manifest_bytes_and_hashes(self):
      m=json.loads((FIX/'manifest.json').read_text());self.assertEqual(len(m),49)
      for n,a in m.items():
        d=(FIX/n).read_bytes();self.assertEqual(len(d),a['bytes'],n);self.assertEqual(hashlib.sha256(d).hexdigest(),a['sha256'],n)
    def test_benign_zip_and_streaming_profiles(self):
      for name in ['paragraphs-tables.docx','types-and-formulas.xlsx','signed-descriptors.docx','namespace-alias.xlsx','rooted-target.xlsx','date1904.xlsx']:
        d=(FIX/name).read_bytes();parts=stream_oracle(d,metadata(d));self.assertIn('[Content_Types].xml',parts)
        for p,b in parts.items():bounded_xml(b)
    def test_malicious_zip_metadata_and_real_streamed_bytes(self):
      names=['duplicate.docx','case-collision.docx','traversal.docx','absolute.docx','backslash.docx','percent.docx','encrypted.docx','symlink.docx','truncated.docx','bad-crc.docx','forged-small-size.docx','bomb.docx','macro.docx','header-mismatch.docx','overlap.docx','zip64.docx','unsupported-method.docx']
      for n in names:
        with self.subTest(n=n),self.assertRaises((Rejected,zlib.error)):
          d=(FIX/n).read_bytes();stream_oracle(d,metadata(d))
    def test_xml_attacks_are_real(self):
      for n in ['entity.docx','depth.docx','malformed-xml.docx','utf16-xml.docx']:
        d=(FIX/n).read_bytes();parts=stream_oracle(d,metadata(d))
        with self.subTest(n=n),self.assertRaises(Rejected):bounded_xml(parts['word/document.xml'])
      d=(FIX/'long-string.docx').read_bytes()
      parts=stream_oracle(d,metadata(d))
      with self.assertRaises(Rejected):bounded_xml(parts['word/document.xml'])
    def test_meaningful_docx_fixture_content(self):
      d=(FIX/'paragraphs-tables.docx').read_bytes();parts=stream_oracle(d,metadata(d));root=bounded_xml(parts['word/document.xml']);ns={'w':'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
      self.assertEqual([e.text for e in root.findall('.//w:t',ns)],['Hello café','世界','Next line','Fruit','Count','Kiwi','4'])
      self.assertEqual(len(root.findall('.//w:tr',ns)),2)
    def test_spreadsheet_fixture_has_real_cell_type_and_cache_coverage(self):
      d=(FIX/'types-and-formulas.xlsx').read_bytes();parts=stream_oracle(d,metadata(d));root=bounded_xml(parts['xl/worksheets/sheet1.xml']);ns={'s':'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
      cells={c.get('r'):c for c in root.findall('.//s:c',ns)}
      self.assertEqual({c.get('t','n') for c in cells.values()},{'s','inlineStr','n','b','e','d'})
      self.assertIsNotNone(cells['A3'].find('s:f',ns));self.assertEqual(cells['A3'].find('s:v',ns).text,'42.50')
      self.assertIsNone(cells['B3'].find('s:v',ns));self.assertEqual(cells['C3'].find('s:v',ns).text,'60')
    def test_relationship_escape_and_external_targets_are_real(self):
      ns='{http://schemas.openxmlformats.org/package/2006/relationships}'
      for n,target in [('relationship-traversal.xlsx','../../outside.xml'),('external-worksheet.xlsx','https://example.invalid/sheet.xml')]:
        d=(FIX/n).read_bytes();parts=stream_oracle(d,metadata(d));r=bounded_xml(parts['xl/_rels/workbook.xml.rels']);self.assertEqual(r[0].get('Target'),target)
      self.assertEqual(ns+'Relationships',r.tag)
    def test_csv_fixture_semantics(self):
      rows=list(csv.reader(io.StringIO((FIX/'structured.csv').read_text()),strict=True))
      self.assertEqual(rows,[['name','value','note'],['kiwi','4','a,b'],['café','5','line one\nline two'],['a"b','0','']])
      with self.assertRaises(csv.Error):list(csv.reader(io.StringIO((FIX/'bad.csv').read_text()),strict=True))
    def test_native_test_fixture_references_are_resolvable(self):
      source='\n'.join(p.read_text() for p in (ROOT/'Tests').glob('*.swift'))
      names=set(re.findall(r'"([^"\n]+\.(?:docx|xlsx|csv|tsv))"',source)) - {'link.docx'}
      self.assertGreaterEqual(len(names),49)
      for n in names:self.assertTrue((FIX/n).is_file(),n)
    def test_production_security_contracts_and_no_remote_execution_surface(self):
      sources={p.name:p.read_text() for p in (ROOT/'JarvisEVO/Services').glob('*.swift')};all_source='\n'.join(sources.values())
      self.assertEqual(len(sources),5)
      for forbidden in ['URLSession','WKWebView','Process(','extractAll','to: url','evaluateJavaScript']:
        self.assertNotIn(forbidden,all_source)
      for required in ['O_NOFOLLOW','fstat(fd','maximumExpandedBytes - total','m.expanded - actual','actual == m.expanded','crc == m.crc','shouldResolveExternalEntities = false','<!DOCTYPE','<!ENTITY','formula cache unavailable','date1904']:
        self.assertIn(required,all_source)
    def test_frozen_base_sources_remain_identical_to_patch_inputs(self):
      for p,sha in json.loads((ROOT/'proposed/base-source-sha256.json').read_text()).items():
        self.assertEqual(hashlib.sha256((Path('/workspace/shared/Jarvis-EVO-recovery-next')/p).read_bytes()).hexdigest(),sha,p)
    def test_dependency_provenance_and_license(self):
      p=json.loads((ROOT/'provenance/ZIPFoundation-provenance.json').read_text())
      self.assertEqual(p['commit'],'22787ffb59de99e5dc1fbfe80b19c97a904ad48d');self.assertEqual(p['version'],'0.9.20');self.assertEqual(p['license'],'MIT')
      self.assertIn('Permission is hereby granted',(ROOT/'provenance/ZIPFoundation-LICENSE.txt').read_text())

if __name__=='__main__':unittest.main(verbosity=2)
