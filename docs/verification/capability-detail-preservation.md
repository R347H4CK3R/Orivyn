# Capability prerequisite preservation

Base: 1fe9fe2. get_app_info previously returned only capability IDs and statuses,
losing the manifest's permission and verification caveats. This change preserves
whole detail strings, bounded to 1,024 UTF-8 bytes each, within the existing
4,096-byte result budget. Whole trailing capabilities may be omitted with explicit
resultTruncated/omittedItems metadata. Oversized or malformed prerequisites fail
closed rather than being shortened into misleading claims.

The additive result schema permits legacy {id,status} records and new
{id,status,detail} records. Swift and JavaScript completion validators reject
unknown keys, empty/control-character detail and oversized detail. Old durable
records remain readable. No new tool, execution permission or automatic action is
introduced. The orchestration inventory remains unchanged.

Bundled descriptions now mention existing saved memory, reviewed local tasks and
archive preparation/review, with conditional scope and private-archive/device
limitations. The calculator description distinguishes its manual screen and
reviewed exact-expression adapter from direct chat. It does not advertise planned
model-selected chat orchestration as functioning.

Regressions were observed before production changes in both Swift and JavaScript
schema checks. Updated tests cover legacy recovery, full detail preservation,
explicit omission counts, malformed data and bounds. The native bundled-resource
XCTest was authored but has not run on Apple here. Source guards and synthetic
checks do not establish model quality or device/release readiness. No CI dispatched.

Final local evidence: 569 Foundation XCTest cases passed (existing Linux redirect
fixture exclusion unchanged); 153 Node reducer tests passed, no skips; 271 Python
tests passed with the existing real-tokenizer skip. The temporary exact-source
Swift probe loaded the actual bundled JSON, produced 4,004 bytes containing 15 of
16 complete capability records, verified omittedItems=1 and every retained detail,
and passed production completion-policy validation. This probe was not an Apple
resource-bundle or device test. git diff --check passed.
