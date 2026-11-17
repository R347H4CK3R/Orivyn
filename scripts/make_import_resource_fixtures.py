#!/usr/bin/env python3
"""Synthetic resource fixtures only; no private export or media."""
import argparse,json,pathlib,zipfile,runpy

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
    return len(dense)
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=pathlib.Path,required=True)
    args=parser.parse_args();print('Dense conversations bytes:',generate(args.output))
