# Built-in chat policy context regression

Native run 43831489212 (source 50cfa819, integrated locally as cebfc53) failed 173/180.
The first conversation-model probe failed before generation: the full built-in system policy,
capability summary and default style exceeded the real tokenizer system allowance. The engine
uses 2,048 context tokens, reserves 1,024 output tokens, and limits system content to half the
remaining input allowance (512 tokens). This was not a refusal from the model.

This change compacts built-in policy prose and removes redundant example synonyms from the
prompt inventory. The actual parser and inventory cases are unchanged. Coding assistance,
no-echo style, recorded-result requirements, bounded local reads, loop exclusions, concrete
local Automatic resolution, local-only connected suggestions, user exact-call review,
authentication/approval distinction, no arbitrary installation and text/OCR limits remain.
User preferences and memories are not truncated; context/output limits and tokenizer guards
are unchanged. The <=1,900-byte policy test detects prose growth but is not tokenizer proof.
The unchanged pinned-model native gate must still pass before this fix is verified on iOS.

Separate actual-loop failures in that run copied the schema placeholder `1..256 UTF-8 bytes`
as a search query. Both real reads returned no matches, then hit the duplicate-call guard.
Automatic selected the correct installed pinned Q4 model with no download. Those failures
are not evidence that context or decision budgets should be raised; their instruction repair
is owned by the loop implementation change. No acceptance assertions are relaxed here.

Final local validation: 587 exact-source Foundation tests passed (0 failures).
Independent review corrected receipt wording to avoid treating arbitrary rendered text as
execution proof. Native tokenizer and actual-model rerun remain pending, not passed here.
