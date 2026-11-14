# Actual remote-parser execution

RemoteEndpoint, SSEDecoder and SSEByteDecoder moved unchanged from OpenAICompatibleProvider.swift into RemoteStreamDecoding.swift; ProviderError moved unchanged out of AIProvider.swift. This allows exact production parser/value tests without fake chat/iOS dependencies. All13prior provider tests passed in proof-29-remote-stream.

Two new tests exposed CR-only streams never dispatching and CRLF consuming one extra byte at the line-limit boundary (five assertions failed). SSEByteDecoder now dispatches CR immediately and suppresses exactly one following LF, handling CR/LF/CRLF across incoming-byte boundaries. Line limits count content, not delimiters. Independent review found no flaw.

235selectedSwift tests pass including15provider cases,132Python tests pass,188Swift files syntax-parse. RED proof-30-remote-newlines-red and GREEN proof-31-remote-newlines-green retain exact manifests and logs. Existing finish-status, unsupported-tool, refusal, token/output bounds and native networking integration remain intact. No claim of full multiline SSE interoperability: this provider still expects one JSON data line per message. No actual provider request, hosted inference cost, iOS network/API validation or release.

## SSE event framing follow-up

The previously documented multiline limitation is now repaired. Independent actualSwift reproduction found valid split JSON rejected at first data line and an initialUTF8BOM silently discarding first content. Three regression methods failed with6assertions (including2thrown invalidResponse errors). Byte framing now accumulates data fields, strips exactly one optionalASCIIspace, joins values withLF, and dispatches only at blank event separators. One initialBOM is stripped as a Unicode scalar; comments/metadata do not alter payload. Both raw line and aggregate event bytes are bounded before append, including insertedLF. Event payload limit999995 reserves5bytes for existing decoder interface.

Existing byte tests now include standard blank separators rather than expecting premature line dispatch; token/content assertions retained. Added bounds, interleaved metadata, invalidUTF8, unterminatedDONE tests.21provider tests and241total selectedSwift tests pass in proof-34-sse-bounds;132Python pass;188Swiftfiles syntax-parse. Reviewer independently recompiled original failures and verified multiline andBOM content now preserved.

Strictly unterminated events are not accepted atEOF, includingDONE. No automatic reconnect, eventID persistence, or real provider/network/iOS verification claimed. No release/catalog changes.
