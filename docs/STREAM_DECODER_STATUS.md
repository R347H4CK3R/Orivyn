# Incremental local streaming decoder

Candidate implementation only; native Swift/runtime behavior unverified.

Previously any invalid UTF-8 byte caused the accumulator to retain all subsequent bytes until finish(), preventing otherwise valid streaming output from displaying. The revised decoder emits the complete prefix immediately using Swift replacement semantics for known-invalid input, and retains only a possibly valid incomplete trailing scalar (up to3bytes). Valid scalars split across model tokens remain unbroken; ASCII before a split scalar no longer waits for the remainder. finish() flushes any incomplete tail once. This is text decoding, not a model quality or Unicode-rendering guarantee.

Eight native tests authored for all split points of representative Unicode, bytewise input, immediate valid output, malformed sequences, empty append/finish, repeated invalid bytes, and bounded buffering. Native tests remain uncompiled/unrun. Two portable source guards failed before implementation and now pass; full portable suite130Python/70agentJS/39VMJS passes. No paid CI or release.

Latest validation update: the Foundation-only algorithm tests now compile and pass under actual Swift6.0.3 on Linux (25 tests combined). Earlier unrun statements describe the prior gate. iOS integration/UI/device tests remain unrun. See FOUNDATION_SWIFT_VALIDATION.md.
