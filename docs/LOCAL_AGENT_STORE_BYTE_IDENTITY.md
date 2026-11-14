# Exact task-store identity

LocalAgentError moved unchanged from JavaScriptCore-dependent LocalAgentCore.swift into a Foundation-only file. This permits actual LocalAgentStore filesystem tests without a fake reducer or framework.

A real regression showed a same-revision save of decomposedUnicode JSON overwriting composedUnicode JSON because Swift String equality compares canonical equivalence. Same-revision saves now require exactUTF8bytes, preserving byte-identical idempotent retry and strictly increasing revision rules. Five filesystem tests cover this, revision rollback/conflicting writes, archive capacity/restoration, corrupt-record preservation, and symlink read/write rejection. Two assertions failed before and pass after;246totalSwift tests pass,134Python pass,190Swiftfiles syntax-parse. Independent review found no flaw.

Proof-38-agent-store-red and proof-39-agent-store-green preserve source manifests and full logs. This tests storage, not model reasoning or nativeJavaScriptCore integration. Full first-save task schema still relies on trusted reducer validation; the store checks size/identity and revision consistency, not a replacement reducer. iOS file-protection effectiveness remains unverified. No release or catalog change.
