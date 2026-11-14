# Local attachment availability boundary

LocalPromptBuilder previously skipped missing/empty extracted text without telling the model an attachment was unavailable. Image limitations were also dependent on imported OCR text surviving excerpt truncation. This affected legacy/imported metadata and a zero/small excerpt budget.

The builder now counts unavailable attachment text explicitly and adds the existing text-only image notice outside excerpt truncation. This is prompt guidance, not proof that a language model will obey or a general hallucination safeguard. Source attachments and typed text are unchanged; no pixels are sent to a text-only model.

Three new XCTest cases fail with five assertions against the old implementation (attachment-availability-red); all 257 Foundation XCTest cases pass after the change (attachment-availability-green). Both use exact production source. The Linux URLProtocol redirect limitation remains excluded, not passed. The three tests are included in the unexecuted native gate.

The actual-engine regression is recorded separately. No claim of native image import, OCR accuracy, visual understanding or iPhone execution is made.
