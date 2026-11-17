"""Static wiring guard only; token fitting behavior needs native tests."""
from pathlib import Path
import re, unittest
ROOT=Path(__file__).resolve().parents[2]
class AttachmentFittingContract(unittest.TestCase):
 def test_engine_uses_tokenizer_aware_preparation(self):
  s=(ROOT/'JarvisEVO/Providers/Local/LlamaEngine.swift').read_text()
  # Ignore formatting, but preserve the production tokenizer/formatter data flow.
  compact=re.sub(r'\s+', '', s)
  start=compact.index('letcountFormatted:([LocalPromptMessage])throws->Int=')
  end=compact.index('//Completenativetranscript',start)
  preparation=compact[start:end]
  self.assertIn('maxTokens:request.maxTokens,contextSize:Int(contextSize)',preparation)
  self.assertIn('messages=tryLocalPromptBuilder.prepareMessages(from:request.messages,maxTokens:request.maxTokens,contextSize:Int(contextSize),tokenCount:countFormatted)',preparation)
  self.assertIn('ifletinput=request.normalChatPrompt{tryrequest.validateInternalModes()messages=tryinput.prepare(maxTokens:request.maxTokens,contextSize:Int(contextSize),tokenCount:countFormatted)',preparation)
  self.assertIn('llama_model_get_vocab(owned.model)',preparation)
  self.assertIn('returntrytokenCount(format(entries,systemPrompt:request.systemPrompt,model:owned.model,conciseQwen3:request.conciseQwen3),vocabulary:vocab)',preparation)
  self.assertIn('prompt=tryformat(messages,systemPrompt:request.systemPrompt,model:model,conciseQwen3:request.conciseQwen3)',preparation)
  self.assertIn('lettokens=trytokenize(prompt,vocabulary:vocabulary)',compact[end:])
  self.assertIn('tokens.count+request.maxTokens<=Int(contextSize)',compact[end:])
 def test_composer_explains_excerpt_scope(self):
  s=(ROOT/'JarvisEVO/UI/RootView.swift').read_text()
  self.assertIn('Models may receive shortened text excerpts',s)
  self.assertIn('Open an attachment to search its stored extracted text',s)
if __name__=='__main__':unittest.main()
