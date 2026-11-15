#!/usr/bin/env python3
import json,pathlib,sys,uuid

def verify(path,previous=None):
 files=list(pathlib.Path(path).glob('*.json'))
 if len(files)!=1:raise ValueError('Exactly one synthetic task required')
 state=json.loads(files[0].read_text())
 if not isinstance(state,dict):raise ValueError('Expected state object')
 for key in ('version','approvalRevision','steps','revision'):
  if type(state.get(key)) is not int:raise ValueError('Expected integer '+key)
 if state['revision']<0:raise ValueError('Invalid revision')
 expected={'schema':1,'steps':[{'name':'get_app_info','arguments':{}},{'name':'search_memory','arguments':{'query':'Cedar acceptance final','limit':3}}]}
 if json.dumps(state.get('completionContract'),sort_keys=True)!=json.dumps(expected,sort_keys=True):raise ValueError('Exact contract mismatch')
 for k,v in dict(version=3,approvalRevision=0,revision=0,status='ready',steps=0,history=[],pending=None,answer=None,error=None,completionContract=expected,goal='Inspect app and Cedar acceptance memory').items():
  if k not in state or state[k]!=v:raise ValueError('Unexpected task '+k)
 if not isinstance(state.get('id'),str):raise ValueError('Missing task ID')
 try:identity=uuid.UUID(state['id'])
 except ValueError:raise ValueError('Invalid task ID')
 if files[0].stem!=str(identity).upper():raise ValueError('Task filename mismatch')
 if previous is not None and state!=previous:raise ValueError('Task changed across relaunch')
 return state
if __name__=='__main__':
 before=verify(sys.argv[1]);verify(sys.argv[2],before);print(json.dumps(before,indent=2))
