#!/usr/bin/env python3
"""Synthetic resource fixtures only; no private export or media."""
import argparse,json,pathlib,zipfile,runpy,struct,zlib

def dat_media():
    # Generated 2x2 RGB PNG, not downloaded or user-provided media.
    def chunk(kind, body):
        return struct.pack('>I', len(body)) + kind + body + struct.pack('>I', zlib.crc32(kind + body) & 0xffffffff)
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 2, 2, 8, 2, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(b'\0\xff\0\0\0\xff\0' + b'\0\0\0\xff\xff\xff\xff')) + chunk(b'IEND', b'')
    text = b'BT /F1 12 Tf 20 100 Td (Synthetic DAT PDF acceptance.) Tj ET\n'
    objects = [b'<< /Type /Catalog /Pages 2 0 R >>', b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
        b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 150] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
        b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
        b'<< /Length ' + str(len(text)).encode() + b' >>\nstream\n' + text + b'endstream']
    pdf = b'%PDF-1.4\n'; offsets = [0]
    for index, obj in enumerate(objects, 1):
        offsets.append(len(pdf)); pdf += str(index).encode() + b' 0 obj\n' + obj + b'\nendobj\n'
    xref = len(pdf)
    pdf += b'xref\n0 6\n0000000000 65535 f \n' + b''.join(f'{offset:010d} 00000 n \n'.encode() for offset in offsets[1:])
    pdf += b'trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n' + str(xref).encode() + b'\n%%EOF\n'
    return {'assets/reviewed-text.dat': b'Synthetic reviewed DAT text.\n',
            'assets/reviewed-image.dat': png, 'assets/reviewed-pdf.dat': pdf,
            'assets/malformed-image.dat': b'\x89PNG\r\n\x1a\ntruncated',
            'assets/malformed-pdf.dat': b'%PDF-not a real document'}

def generate(output):
    output.mkdir(parents=True,exist_ok=True)
    record={'id':'00000000-0000-0000-0000-000000000001','title':'Dense synthetic import',
      'current_node':'n','create_time':1,'update_time':1,'mapping':{'n':{'parent':None,
      'message':{'id':'00000000-0000-0000-0000-0000000186a1','author':{'role':'user'},
      'create_time':1,'content':{'content_type':'text','parts':['Retained synthetic message']}}}}}
    prefix=json.dumps(record,separators=(',',':'))[:-1]
    item=json.dumps({'a':'x'*32,'b':1,'c':False},separators=(',',':'))
    dense=('['+prefix+',"unused_metadata":['+','.join([item]*279000)+']}]').encode()
    assert len(dense)<16_000_000
    malformed=('['+prefix+',"unused_metadata":[{},]}]').encode()
    for name,body in [('dense-metadata.zip',dense),('malformed-metadata.zip',malformed)]:
        with zipfile.ZipFile(output/name,'w',compression=zipfile.ZIP_DEFLATED) as archive:
            entry=zipfile.ZipInfo('conversations.json',(2026,1,1,0,0,0));entry.compress_type=zipfile.ZIP_DEFLATED
            archive.writestr(entry,body)
    # Reuse the exact public synthetic acceptance fixture, never user input.
    fixture = pathlib.Path(__file__).resolve().parents[1] / 'Diagnostics/ArchiveRestore/make_fixture.py'
    manual = output / 'manual-attachments.zip'
    manual.unlink(missing_ok=True)
    runpy.run_path(str(fixture))['create'](manual)
    with zipfile.ZipFile(manual) as source, zipfile.ZipFile(output / 'dat-attachments.zip', 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        for entry in source.infolist():
            archive.writestr(entry, source.read(entry.filename))
        for name, body in dat_media().items():
            entry = zipfile.ZipInfo(name, (2026, 1, 1, 0, 0, 0)); entry.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(entry, body)
    return len(dense)
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=pathlib.Path,required=True)
    args=parser.parse_args();print('Dense conversations bytes:',generate(args.output))
