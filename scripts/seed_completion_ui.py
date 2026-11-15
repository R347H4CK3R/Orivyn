#!/usr/bin/env python3
"""Seed a verified model only inside an exact simulator UI-test container."""
import argparse,hashlib,json,os,pathlib,re,shutil,subprocess,sys,uuid

def safe_chain(path):
 for p in [path,*path.parents]:
  if p.is_symlink():raise ValueError('Symlink component rejected')

def seed(container,source,model):
 container=pathlib.Path(container);source=pathlib.Path(source)
 if not container.is_absolute() or not container.is_dir():raise ValueError('Missing absolute container')
 safe_chain(container);safe_chain(source)
 name=model['fileName']
 if pathlib.Path(name).name!=name or name in ('.','..'):raise ValueError('Invalid basename')
 if not source.is_file() or source.stat().st_size!=model['byteCount']:raise ValueError('Model size mismatch')
 digest=hashlib.sha256()
 with source.open('rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''):digest.update(b)
 if digest.hexdigest()!=model['sha256']:raise ValueError('Model digest mismatch')
 target=container/'Library/Application Support/JarvisEVOUITests/Models'
 safe_chain(target)
 if target.exists() and list(target.iterdir()):raise ValueError('Refuse to replace existing model data')
 target.mkdir(parents=True,exist_ok=True)
 dest=target/name
 with source.open('rb') as src,dest.open('xb') as out:shutil.copyfileobj(src,out)
 h=hashlib.sha256()
 with dest.open('rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
 if h.hexdigest()!=model['sha256'] or dest.stat().st_size!=model['byteCount']:raise ValueError('Copied model mismatch')
 temporary=target/('.manifest-'+str(uuid.uuid4()))
 with temporary.open('x') as f:json.dump([model],f);f.flush();os.fsync(f.fileno())
 os.replace(temporary,target/'installed-models.json')
 return target

if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--simulator',required=True);p.add_argument('--model',required=True);a=p.parse_args()
 if os.environ.get('GITHUB_ACTIONS')!='true' or os.environ.get('RUNNER_ENVIRONMENT')!='github-hosted':raise ValueError('Hosted CI only')
 if not re.fullmatch(r'[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}',a.simulator):raise ValueError('Exact UUID required')
 raw=subprocess.check_output(['xcrun','simctl','get_app_container',a.simulator,'app.jarvisevo.ios','data'],text=True).strip()
 safe_chain(pathlib.Path(raw));safe_chain(pathlib.Path(a.model))
 c=pathlib.Path(raw).resolve(strict=True)
 expected='/CoreSimulator/Devices/'+a.simulator+'/data/Containers/Data/Application/'
 if expected not in str(c) or not re.fullmatch(r'[0-9A-Fa-f-]{36}',c.name):raise ValueError('Unexpected simulator container')
 sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/'Diagnostics/NativeTools'))
 from download import select
 m=select('qwen3-1.7b-q4_k_m');m={k:m[k] for k in ('fileName','sha256','byteCount')};m.update(id='qwen3-1.7b-q4_k_m',name='Pinned Qwen3 UI fixture',license='Apache-2.0')
 print(seed(c,pathlib.Path(a.model).resolve(strict=True),m))
