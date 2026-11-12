#!/usr/bin/env python3
"""Development-time exact public assets. No app runtime downloader or guest image."""
from pathlib import Path
import hashlib,io,json,os,tarfile,tempfile,urllib.request
ROOT=Path(__file__).resolve().parent
PACKAGE_URL='https://registry.npmjs.org/v86/-/v86-0.5.473.tgz'
PACKAGE_SHA256='364ab67a68c1d83646e2ddf7caf73c24574694a132b2b43689ad0f72e7242636'
COMMIT='315b2b0b758703ef0e6cc7b4088d6068f83f3c20'
def verified(data,expected):
    if len(data)!=expected['bytes'] or hashlib.sha256(data).hexdigest()!=expected['sha256']:raise ValueError('Pinned asset mismatch')
    return data
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,*args,**kwargs):raise ValueError('Unexpected asset redirect')
def download(url,maximum):
    with urllib.request.build_opener(NoRedirect()).open(url,timeout=45) as response:
        if response.status!=200:raise ValueError('Asset response refused')
        data=response.read(maximum+1)
        if len(data)>maximum:raise ValueError('Asset too large')
        return data

def package_files(data,files):
    if hashlib.sha256(data).hexdigest()!=PACKAGE_SHA256:raise ValueError('Package checksum mismatch')
    result={}
    with tarfile.open(fileobj=io.BytesIO(data),mode='r:gz') as archive:
        for name in ['libv86.js','v86.wasm']:
            member=archive.getmember('package/build/'+name)
            if not member.isfile() or member.size!=files[name]['bytes']:raise ValueError('Invalid package member')
            result[name]=verified(archive.extractfile(member).read(member.size+1),files[name])
    return result

def main():
    files=json.loads((ROOT/'PINNED_ASSETS.json').read_text())['files'];pending={}
    for name,expected in files.items():
        path=ROOT/'Assets'/name
        if path.is_symlink():raise ValueError('Symlink output refused')
        if path.exists():verified(path.read_bytes(),expected)
        else:pending[name]=expected
    if any(name in pending for name in ['libv86.js','v86.wasm']):
        package=package_files(download(PACKAGE_URL,5*1024*1024),files)
    else:package={}
    prepared={}
    for name,expected in pending.items():
        prepared[name]=package[name] if name in package else verified(download(f'https://raw.githubusercontent.com/copy/v86/{COMMIT}/bios/{name}',expected['bytes']),expected)
    for name,data in prepared.items():
        fd,path=tempfile.mkstemp(prefix='.asset-',dir=ROOT/'Assets')
        try:
            with os.fdopen(fd,'wb') as out:out.write(data)
            os.replace(path,ROOT/'Assets'/name)
        finally:
            if os.path.exists(path):os.unlink(path)
    print('Four exact public engine/ROM assets verified; no guest downloaded')
if __name__=='__main__':main()
