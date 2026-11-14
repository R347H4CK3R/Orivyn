# Exact Unicode schema identity

Actual Swift reproduction showed Swift canonical-equivalence String/Dictionary matching accepted a decomposed e+accent string/key where the schema allowed only composed é, then transmitted different JSON bytes unchanged. This affects enum, required and additional-property validation.

Schema matching now compares UTF-8 sequences (unique for valid Unicode codepoint sequences) for string enum values, required schema names, required argument presence and declared-property dispatch. It never rewrites or normalizes supplied input. Unknown additional keys retain the schema additionalProperties policy instead of inheriting a canonically equivalent property's constraints. Existing canonical-collision rejection in parser and required-name uniqueness remains conservative/fail-closed. Property scanning is bounded to64 entries.

Five actual production regression cases failed before this change and pass afterward. Full exact-source Swift6.1.3Linux subset:204 tests pass. 132Python tests pass;184Swift files syntax-parse. Independent read-only review found no concrete defect. Logs/manifests retained at proof-19-unicode-red and proof-20-unicode-green.

No real external plugin invocation or iOS API/device validation performed. Existing unsupported Linux redirect fixture and Observation linker limits remain. No release/catalog changes.
