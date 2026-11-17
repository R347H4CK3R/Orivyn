# Legacy export attachment map: evidence and supported subset

Research date: 2026-11-17. No private exports were inspected or uploaded. Test data
is synthetic. This is not an official OpenAI format guarantee and does not prove
that any particular user's export has the supported structure.

## Primary implementation evidence

1. [fgault/chatgpt-archive-enhancer](https://github.com/fgault/chatgpt-archive-enhancer/blob/main/chatgpt_archive_enhancer.py)
   parses a `var assetsJson` declaration with a JSON decoder. Its processing code
   intersects map keys with `message.id` collected from conversation mappings,
   treats map values as arrays of exact ZIP paths, and reads those paths directly.
   The script's rendered viewer also looks up assets by message ID. This is
   implementation evidence, not a publication of the original export template.
2. [hibaruzakura-code/chatgpt-archive-tool](https://github.com/hibaruzakura-code/chatgpt-archive-tool/blob/main/make_chat_archive.py)
   independently locates `var assetsJson =` in `chat.html`, JSON-decodes a dictionary
   of string arrays, and uses message IDs to retrieve media paths. Its permissive
   path repair and fallback IDs are NOT copied into Orivyn.
3. [knu/chatgpt2obsidian](https://github.com/knu/chatgpt2obsidian/blob/main/chatgpt2obsidian)
   likewise identifies message-keyed arrays in embedded `assetsJson`. Its later
   filename-prefix matching is NOT evidence for exact attachment reference mapping
   and is NOT adopted.
4. [OpenAI export help](https://help.openai.com/en/articles/7260999-exporting-your-chatgpt-history-and-data)
   describes export contents and the current viewer but does not specify this
   attachment schema. `index.html` is not assumed to have the legacy structure.

Public converters identify the declaration with the literal-name pattern
`var\s+assetsJson\s*=\s*` and decode a following JSON object. The following is a
SYNTHETIC minimal instance of that observed shape, not a copied user export:

```html
<script>
var jsonData = [];
var assetsJson = {"12345678-1234-1234-1234-123456789abc":["assets/picture.png"]};
</script>
```

## What the other metadata does not prove

[Firsthand export report](https://github.com/mohamed-chs/convoviz/issues/70)
identifies `conversation_asset_file_names.json` as physical path to display name.
[Converter format documentation](https://github.com/difegam/chatgpt-to-markdown/blob/main/docs/explanation/export-format.md)
shows `export_manifest.json` entries containing path and size. Neither establishes
an exact message/reference ID to physical path mapping without inference.
`ArchiveAttachmentAssociation.Mapping` is our coordinator-supplied contract, not
an observed exporter schema. Existing helper tests must not be cited as format
proof.

## Parser contract and deliberate unsupported cases

`LegacyArchiveAssetMap.parse(Data) throws -> [UUID: [String]]` is inert. It makes
no filesystem accesses, executes no HTML/JavaScript, fetches no URL and neither
activates attachments nor clears unresolved content records.

- UTF-8 input at most 64 MiB. Only plain inline `<script>` elements (case-insensitive
  tag spelling, optional whitespace, no attributes) are supported. HTML comments,
  quoted tag attributes and raw-text style/title/textarea/xmp/iframe/noembed/noframes
  content are not searched as executable declarations. Ambiguous HTML contexts
  including template, noscript, SVG, MathML and plaintext are unsupported.
- A candidate is a top-level, statement-start `var assetsJson = {JSON};`. Spaces
  may separate these tokens; comments embedded inside that declaration are not
  supported. Semicolon is required. A preceding `var jsonData = ...;` is allowed.
- The conservative script lexer skips ordinary quoted strings and comments and
  tracks balanced parentheses/brackets/braces. Templates, regex/division slash,
  escaped identifiers, non-ASCII code tokens and Unicode line separators are
  unsupported. Unrelated renderer JavaScript using those constructs therefore
  makes the export unsupported too. This is deliberately NOT a general JS parser.
- Exactly one declaration is allowed across the document. Missing maps, duplicate
  declarations, top-level reassignment/use ambiguity, invalid JSON, duplicate keys
  after UUID normalization, unsupported key/value types, and incomplete delimiters
  fail closed. Nothing is returned partially.
- Keys must be canonical hyphenated UUIDs, case-insensitive; JSON escape spelling
  is decoded before duplicate checks. No node-ID fallback or non-UUID invention.
- JSON at most 4 MiB; at most 20,000 message entries and 20,000 total paths;
  at most 32 paths per message. Individual paths at most 4,096 UTF-8 bytes,
  64 components and 255 bytes per component.
- Paths are exact strings. Absolute/empty/dot/dot-dot components, backslashes,
  control characters, colons and percent signs are rejected. There is no URL
  decoding, basename/suffix matching, display-name matching or separator repair.
  Duplicate paths within a message are rejected; cross-message shared paths are
  allowed. No claim is made that a message's path matches one particular opaque
  content part or attachment-metadata record.

## Integration obligations

A UUID key alone is not provenance. The coordinator must bind it unambiguously to
one external message ID in the preserved source, then intersect with messages
actually imported through existing branch/privacy filters and the immutable text
receipt. Reject ambiguity across conversations. Do not associate hidden/system
messages or infer an exported reference-to-file relationship from path count.

Revalidate exact root-relative paths through no-follow descriptors and preserve
hash/size evidence through copying. Only the existing supported attachment importer
may activate compatible image/PDF/text files within its limit; opaque unsupported
blobs remain unlinked. Existing committed jobs require a separately reviewed,
retry-safe supplemental association transaction, never mutation of the original
text import receipt. Preserve all original files and unresolved record evidence.

## Renderer compatibility assessment (not a positive release gate)

The public fgault enhancer source was downloaded read-only and its `ONLOAD`
constant extracted with Python AST literal inspection, without executing that
program. Its unmodified 5,051-character renderer was combined with synthetic
`jsonData` and the synthetic one-message map. The exact production parser returned
`unsupported`: the renderer contains regular-expression literals in `anchorId`
and `cleanTitle`. This establishes a real compatibility limitation, NOT successful
compatibility with a common exporter or official template. No unmodified original
OpenAI legacy renderer has been validated by this work.

Public source SHA-256: `b043a85ed2c6342b7977fd1af8cbf281e94f198fe39c8d7f6a126926e740c90d`.
Extracted renderer SHA-256: `a6c0198f5834994c5e7e56d6bdf715a7a82aca48d660940a5441839af9a65825`.
Synthetic-wrapper fixture SHA-256: `e41bdcf7cd9363686416e268fc1712949f53c5b5c45e42f1733cfb1f8378c2e7`.

Annex B HTML-like script comments (`<!--` and `-->`) are now conservatively rejected
outside ordinary quoted strings and normal comments. Both reported bypasses were
observed failing regression assertions before this fix, then passing. Ignoring
unparsed renderer suffixes would remove duplicate/reassignment detection and is
not an acceptable shortcut to improve compatibility. Any additional JavaScript
lexical support needs separate adversarial tests and independent review.

The native fixture generators now produce a deliberately minimal synthetic
`chat.html` map and `assets/reviewed-note.txt`. That proves coordinator behavior
only and must not be substituted for the missing positive renderer-compatibility
release gate.
