#!/usr/bin/env python3
"""Development-only pinned public research assets; not app runtime downloading."""
from pathlib import Path
import hashlib,json,os,sys,time,urllib.request
ROOT=Path(__file__).resolve().parent
manifest=json.loads((ROOT/'MODEL_PAIR.json').read_text())
def main():
 target=Path(sys.argv[1]).resolve();target.mkdir(parents=True,exist_ok=True)
 for item in manifest['artifacts']:
  path=target/item['file'];size=item['size'];expected=item['sha']
  if path.is_symlink():raise ValueError('Symlink refused')
  if path.exists():
   with path.open('rb') as f:digest=hashlib.file_digest(f,'sha256').hexdigest()
   if path.stat().st_size!=size or digest!=expected:raise ValueError('Existing research asset mismatch')
   continue
  partial=path.with_suffix('.partial');start=time.monotonic();count=0;digest=hashlib.sha256()
  try:
   with urllib.request.urlopen(f'https://huggingface.co/{manifest["repository"]}/resolve/{manifest["revision"]}/{item["file"]}',timeout=60) as response, partial.open('xb') as out:
    if response.status!=200 or not response.url.startswith('https://'):raise ValueError('Invalid response')
    while chunk:=response.read(1024*1024):
     count+=len(chunk)
     if count>size or time.monotonic()-start>300:raise ValueError('Download budget exceeded')
     out.write(chunk);digest.update(chunk)
    out.flush();os.fsync(out.fileno())
   if count!=size or digest.hexdigest()!=expected:raise ValueError('Research asset integrity mismatch')
   partial.replace(path)
  finally:partial.unlink(missing_ok=True)
  print('Verified',item['file'],size,flush=True)
if __name__=='__main__':main()
