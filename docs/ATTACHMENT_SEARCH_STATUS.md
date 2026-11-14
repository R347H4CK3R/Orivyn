# Offline extracted-text search

Implemented in the local integration candidate, not shipped or native-verified.

Every attachment preview with stored extracted text now offers Search extracted text. This is explicit literal phrase matching with case/diacritic folding, not model reasoning or semantic retrieval. It searches later passages beyond the local chat prompt's first4,000-character attachment excerpt without sending data anywhere or reopening files.

The input prefix is capped at60,000 Swift Characters; the query at256UTF-8 bytes; results at50 nonoverlapping matches with bounded240-character snippets. A51st observed match sets the more-results notice. Truncation and no-match states distinguish searched stored extraction from original document completeness. Offsets are original extracted-text Character positions, displayed one-based, not PDF page numbers. OCR inaccuracies remain. The original data and conversation are unchanged.

Nine native algorithm regressions cover folded Unicode matching, late passages, exact result caps, oversized query, omitted tail, original-source immutability, inert regex/instruction text and composed-emoji bounds. They are authored but uncompiled/unrun. Two portable UI source-contract checks failed before implementation then pass; these do not execute SwiftUI or prove native behavior. Full portable results:123 Python,67 agentJS,39 VMJS pass. No paid CI or release performed.

Latest validation update: the Foundation-only algorithm tests now compile and pass under actual Swift6.0.3 on Linux (25 tests combined). Earlier unrun statements describe the prior gate. iOS integration/UI/device tests remain unrun. See FOUNDATION_SWIFT_VALIDATION.md.
