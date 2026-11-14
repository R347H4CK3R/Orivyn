#!/usr/bin/env python3
"""Run real native lifecycle tests and validate content-free terminal metrics."""
import argparse, hashlib, json, math, pathlib, subprocess
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--model',type=pathlib.Path,required=True)
p.add_argument('--output',type=pathlib.Path,required=True)
a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
root=pathlib.Path(__file__).resolve().parent
(a.output/'SOURCE-MANIFEST.json').write_text(json.dumps({name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in ['bridge.cpp','bridge.h','driver-tests.cpp','build.sh','libOwnedNativeGate.so','driver-tests']},indent=2)+'\n')
with (a.output/'driver.stdout').open('w') as out,(a.output/'driver.stderr').open('w') as err:
    run=subprocess.run([str(root/'driver-tests'),str(a.model.resolve())],stdout=out,stderr=err,timeout=360)
assert run.returncode==0, f'driver failed {run.returncode}; inspect captured logs'
integer_keys={'version','status','prompt_tokens','prompt_decoded','sampled_tokens','generated_tokens','prefill_calls','generation_calls','last_decode_status'}
time_keys={'setup_ms','prefill_ms','sampling_ms','generation_ms','validation_ms','max_decode_ms','elapsed_ms'}
phases={'admission','setup','prefill','sampling','generation','validation'}
records=[]
for line in (a.output/'driver.stderr').read_text().splitlines():
    if not line.startswith('ORIVYN_NATIVE_GENERATION_METRICS '):continue
    pairs=[item.split('=',1) for item in line.split()[1:]]
    assert len(pairs)==len(dict(pairs)), 'duplicate metric'
    value=dict(pairs)
    assert set(value)==integer_keys|time_keys|{'phase'}, 'unexpected field or content'
    assert value['phase'] in phases
    for key in integer_keys:value[key]=int(value[key])
    for key in time_keys:
        value[key]=float(value[key]);assert math.isfinite(value[key]) and value[key]>=0
    assert value['version']==1 and 0<=value['status']<=12
    assert 0<=value['generated_tokens']<=value['sampled_tokens']<=512
    assert 0<=value['prompt_decoded']<=value['prompt_tokens']
    assert value['max_decode_ms']<=value['prefill_ms']+value['generation_ms']+0.01
    assert sum(value[key] for key in ['setup_ms','prefill_ms','sampling_ms','generation_ms','validation_ms'])<=value['elapsed_ms']+0.02
    records.append(value)
assert records
for status in [0,1,2,3,4,9,12]:assert any(x['status']==status for x in records),f'missing original status {status}'
success=[x for x in records if x['status']==0]
assert len(success)>=4
for x in success:
    assert x['phase']=='validation' and x['prompt_tokens']==x['prompt_decoded']>0
    assert x['sampled_tokens']>=x['generated_tokens']>0 and x['generation_calls']>0
    assert x['prefill_ms']>0 and x['generation_ms']>0 and x['validation_ms']>0
expired=[x for x in records if x['status']==3 and x['phase']=='prefill']
assert expired,'real prefill expiry must be distinguishable from generation'
assert any(x['prefill_calls']>0 and x['prompt_decoded']>0 and x['sampled_tokens']==0 and x['generation_calls']==0 and x['max_decode_ms']>0 for x in expired)
assert any(x['status']==3 and x['phase']=='admission' and x['prefill_calls']==0 for x in records)
(a.output/'METRICS.json').write_text(json.dumps(records,indent=2)+'\n')
print(f'PASS {len(records)} actual terminal metric records; original statuses, real prefill expiry, successful generation, count/timing schema; no Apple verification')
