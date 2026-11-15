#!/usr/bin/env python3
"""Whole-response scorer frozen before inference. Never examines image pixels."""
import json, pathlib, re, sys
ROOT=pathlib.Path(__file__).resolve().parent

def normalize(answer):
    # Case/whitespace, one balanced quotation pair, and terminal sentence marks
    # are presentation tolerances. Never remove explanatory or contradictory words.
    value=' '.join(answer.strip().casefold().split())
    value=value.rstrip('.!?').rstrip()
    if len(value)>=2 and (value[0],value[-1]) in [('"','"'),("'","'"),('“','”')]:
        value=value[1:-1].strip()
    return value

def score(case, result):
    answer=result.get('output')
    transport=(result.get('status')==0 and result.get('closeAcknowledged') is True
               and isinstance(answer,str) and 0<len(answer.encode('utf-8'))<=16383)
    report=result.get('report',{})
    native=(isinstance(report.get('tokens'),int) and not isinstance(report.get('tokens'),bool)
            and 0<report['tokens']<128 and report.get('live_resources')==0
            and report.get('positions',0)>0 and report.get('image_chunks')==1)
    match=isinstance(answer,str) and normalize(answer) in case['acceptedNormalizedAnswers']
    return {'id':case['id'],'passed':transport and native and match,
            'runtimeComplete':transport and native,'answerMatched':match,
            'normalizedAnswer':normalize(answer) if isinstance(answer,str) else None}

def evaluate(document):
    frozen=json.loads((ROOT/'FROZEN_CASES.json').read_text())
    results=document['cases']
    expected=[c['id'] for c in frozen['cases']]
    if len(results)!=len(expected) or {r['id'] for r in results}!=set(expected):
        raise ValueError('Require every frozen case exactly once; no dropping failures or duplicate cases')
    byid={r['id']:r for r in results}
    rows=[]
    for case in frozen['cases']:
        result=byid[case['id']]
        if result.get('rgbSHA256')!=case['rgbSHA256'] or result.get('question')!=case['question']:
            raise ValueError('Input pixels or question differ from frozen case '+case['id'])
        rows.append(score(case,result))
    return {'scope':'Frozen synthetic diagnostic only; no broad vision/OCR or device acceptance claim',
            'passed':all(r['passed'] for r in rows),'cases':rows}
if __name__=='__main__':
    result=evaluate(json.loads(pathlib.Path(sys.argv[1]).read_text()))
    print(json.dumps(result,indent=2));sys.exit(0 if result['passed'] else 1)
