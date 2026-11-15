import json,pathlib,sys
from proposal_approval import parse,approve_fields
here=pathlib.Path(__file__).resolve().parent;case,output=sys.argv[1:];output=pathlib.Path(output)
try:
 value=parse((output/'proposal-raw.json').read_text())
 # Protocol metadata is validated independently, not silently discarded.
 expected=json.loads((here/'reviewed-intents.json').read_text())[case]
 assert set(value)==set(expected['intent'])|{'schema'} and type(value['schema']) is int and value['schema']==1
 semantic={key:value[key] for key in expected['intent']}
 ok,reason=approve_fields(json.dumps(semantic,ensure_ascii=False),expected)
except Exception as error:ok,reason=False,'invalid-strict-schema:'+str(error)
(output/'APPROVAL.json').write_text(json.dumps({'approved':ok,'reason':reason,'noRepair':True},indent=2)+'\n')
sys.exit(0 if ok else 1)
