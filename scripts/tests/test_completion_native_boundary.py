import pathlib, unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
class CompletionNativeBoundary(unittest.TestCase):
 def test_session_routes_by_version_and_checks_contract_twice(self):
  s=(ROOT/'JarvisEVO/Services/LocalAgentSession.swift').read_text()
  self.assertIn('if item.version == 3',s)
  self.assertIn('else if item.version == 1',s)
  self.assertGreaterEqual(s.count('LocalCompletionPolicy.derive('),3)
  self.assertIn('GenerationRequest.completionAgent',s)
 def test_engine_grammar_and_internal_mode_exclusivity(self):
  self.assertIn('LocalAgentGrammar.completion(policy)',(ROOT/'JarvisEVO/Providers/Local/LlamaEngine.swift').read_text())
  s=(ROOT/'JarvisEVO/Core/AIProvider.swift').read_text()
  self.assertIn('localCompletionPolicy != nil',s)
 def test_create_api_has_explicit_approval_wiring(self):
  s=(ROOT/'JarvisEVO/Services/LocalAgentCore.swift').read_text()
  self.assertIn('"createContract"',s)
  session=(ROOT/'JarvisEVO/Services/LocalAgentSession.swift').read_text()
  self.assertEqual(session.count('core.call("createContract"'),1)
  self.assertIn('func approveCompletion(',session)
 def test_snapshot_parser_checks_raw_json_before_decoding(self):
  s=(ROOT/'JarvisEVO/Services/LocalAgentCore.swift').read_text()
  self.assertIn('MCPJSONValue.parse(data, maximumBytes: 131_072)',s)
