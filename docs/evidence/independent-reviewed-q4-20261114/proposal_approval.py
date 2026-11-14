"""Independent predeclared intent grading. Never repairs or supplies a proposal."""
import json, math, unicodedata

def canonical(text):
    return unicodedata.normalize('NFC', text).casefold()

def strict_object(pairs):
    result = {}
    for key,value in pairs:
        if key in result: raise ValueError('Duplicate proposal field')
        result[key] = value
    return result

def parse(raw):
    def invalid(value):raise ValueError('Non-JSON numeric constant')
    value=json.loads(raw,object_pairs_hook=strict_object,parse_constant=invalid)
    if not isinstance(value,dict):raise ValueError('Proposal must be an object')
    return value

def approve_fields(raw, expectation):
    """Called on actual proposal fields only after production schema validation.
    JSON field order/escaping and canonical Unicode/case are not semantic changes.
    Explicit user query bytes remain exact. Unknown fields are never discarded.
    """
    proposal=parse(raw);expected=expectation['intent']
    if set(proposal)!=set(expected):return False,'unknown-or-missing-field'
    if proposal.get('kind')!=expected['kind']:return False,'wrong-plan-kind'
    query=proposal.get('query')
    if not isinstance(query,str):return False,'invalid-query'
    if expectation['queryPolicy']=='exact':
        valid=query==expected['query']
    else:
        valid=canonical(query) in {canonical(x) for x in expectation['allowedQueries']}
    if not valid:return False,'query-outside-predeclared-variants'
    if expected['kind']=='conversation_read':
        title=proposal.get('title');indexes=proposal.get('messageIndexes')
        if not isinstance(title,str) or canonical(title)!=canonical(expected['title']):return False,'wrong-target-title'
        if not isinstance(indexes,list) or not 1<=len(indexes)<=3:return False,'invalid-message-indexes'
        # Integral JSON numbers have the same intent; production schema remains authoritative.
        if any(isinstance(x,bool) or not isinstance(x,(int,float)) or not math.isfinite(x) or int(x)!=x or not 0<=x<=9999 for x in indexes):return False,'invalid-message-indexes'
        if len(set(indexes))!=len(indexes) or set(indexes)!=set(expected['messageIndexes']):return False,'wrong-message-indexes'
    return True,'matches-frozen-intent'
