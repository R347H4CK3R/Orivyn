import hashlib,json,pathlib,unittest
from proposal_approval import approve_fields,parse
ROOT=pathlib.Path(__file__).parent
class DesignTests(unittest.TestCase):
 def test_original_and_reviewed_seals(self):
  original=json.loads((ROOT/'DESIGN-FREEZE.json').read_text());reviewed=json.loads((ROOT/'REVIEWED-DESIGN-FREEZE.json').read_text())
  self.assertEqual(hashlib.sha256((ROOT/'sealed-cases.json').read_bytes()).hexdigest(),original['fixtureSHA256'])
  for file,key in [('supplemental-case.json','supplementalSHA256'),('reviewed-intents.json','reviewedIntentSHA256'),('proposal_approval.py','proposalScorerSHA256')]:self.assertEqual(hashlib.sha256((ROOT/file).read_bytes()).hexdigest(),reviewed[key])
 def test_hidden_markers_and_target_indexes(self):
  cases=json.loads((ROOT/'sealed-cases.json').read_text());self.assertEqual(len(cases),8)
  for case in cases:
   self.assertLessEqual(len(case['goal'].encode()),512)
   if case['mode']!='read':continue
   marker=case['marker'];self.assertNotIn(marker,case['goal'])
   target=next(x for x in case['conversations'] if x['id']==case['targetID'])
   for conversation in case['conversations']:self.assertNotIn(marker,conversation['title'])
   text=target['messages'][case['messageIndex']]['content'];self.assertIn(marker,text)
   if case['minimumOffset']:self.assertGreaterEqual(text.encode().index(marker.encode()),case['minimumOffset'])
 def test_all_expected_intents_and_only_predeclared_query_variants(self):
  for expectation in json.loads((ROOT/'reviewed-intents.json').read_text()).values():
   self.assertEqual(expectation['userSelectedKind'],expectation['intent']['kind'])
   self.assertEqual(expectation['kindProvenance'],'predeclared-user-input-not-model-classification')
   expected=expectation['intent'];self.assertTrue(approve_fields(json.dumps(expected),expectation)[0])
   for query in expectation['allowedQueries']:
    self.assertTrue(approve_fields(json.dumps(expected|{'query':query}),expectation)[0])
   self.assertFalse(approve_fields(json.dumps(expected|{'query':'UNRELATED_UNDECLARED_QUERY'}),expectation)[0])
   self.assertFalse(approve_fields(json.dumps(expected|{'approved':True}),expectation)[0])
   self.assertFalse(approve_fields(json.dumps({k:v for k,v in expected.items() if k!='query'}),expectation)[0])
 def test_wrong_scope_and_indexes_cannot_be_auto_approved(self):
  e=next(x for x in json.loads((ROOT/'reviewed-intents.json').read_text()).values() if x['intent']['kind']=='conversation_read');p=e['intent']
  for change in [{'kind':'conversation_search'},{'title':'unrelated'},{'messageIndexes':[0,1,2]},{'messageIndexes':[True]},{'messageIndexes':[1,1]},{'messageIndexes':[1.5]}]:self.assertFalse(approve_fields(json.dumps(p|change),e)[0])
 def test_raw_duplicate_keys_and_non_json_constants_rejected(self):
  for text in ['{"query":"first","query":"second"}','{"outer":{"x":1,"x":2}}','{"query":NaN}','[]']:
   with self.assertRaises(ValueError):parse(text)
 def test_semantically_irrelevant_formatting_not_a_rejection(self):
  e={'intent':{'kind':'conversation_read','query':'Résumé','title':'Résumé','messageIndexes':[1]},'queryPolicy':'predeclared-canonical-variants','allowedQueries':['Résumé']}
  self.assertTrue(approve_fields('{"messageIndexes":[1.0],"title":"RÉSUMÉ","query":"RÉSUMÉ","kind":"conversation_read"}',e)[0])
  e['queryPolicy']='exact';self.assertFalse(approve_fields(json.dumps(e['intent']|{'query':'RÉSUMÉ'}),e)[0])
if __name__=='__main__':unittest.main()
