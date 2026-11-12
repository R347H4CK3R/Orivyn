# Exclusive local resource ownership (design, not implemented)

## Why this is needed before final image/desktop acceptance

The single LlamaEngine caches its last model/context after a turn. Its current `unload()` sets `unloadWhenIdle` while busy and returns, so awaiting that method is not evidence of immediate release. A phone-contained VM, vision model or Apple image-generation session must not be admitted on the assumption that the old language model is gone. There is no universal iOS process memory ceiling; total hardware RAM is only coarse routing guidance.

## Proposed narrow design

An AppModel-owned exclusive-work lease identifies the operation and kind (native image creation, future VM, future vision). Acquisition reserves admission synchronously before awaits, refuses concurrent acquisition and active unfinished composer/history/voice work with an actionable message, and blocks every send/regenerate/voice/automatic path while held. It does not delete installed models or modify the draft. The explicit user action opening a heavy feature triggers acquisition, not navigation alone.

LlamaEngine adds a resource-release method that cancels its owned worker if requested and suspends until that worker's cleanup has finished. It resumes all waiting releasers exactly once after clearing resources and loaded path. Do not hold raw pointers outside the actor, create a second runtime or merely poll a flag. Existing `unload()` behavior remains available for compatible callers until migrated.

Lease acquisition rechecks the owning operation and foreground after awaiting engine release. Cancel, background, memory pressure, thermal shutdown and newer navigation invalidate ownership before awaiting cleanup, so a late release cannot start a retired feature. Image form/VM presentation has one stable owner; release occurs on that outer presentation's dismissal, not a child system sheet's appearance callback. Completed image import is separately owned and bounded; it cannot accidentally release a newer VM lease. A backgrounded VM must pause/stop according to its verified snapshot semantics. Uncertain snapshot persistence is never described as saved.

## Tests before implementation

- Controlled resource boundary proves no launch until actual release, exactly one lease, late completion after cancellation/restart cannot acquire, and draft/files/manual provider remain unchanged.
- All text submit/regenerate/branch/voice/automatic paths reject while a lease is active, before history or network mutation.
- Real native model load → release → reload/inference remains functional; no shared-engine overlap and no stale generation callback.
- Native image sheet cancellation/background and VM Stop/restart exercise actual owner lifecycle without hiding controls.
- Physical iPhone records process memory, OS memory warnings, latency and thermal state across text/image/VM switches. Simulator unit tests do not close that gate.

This is an integration plan only. No final memory-safety or VM/vision acceptance claim follows from this document.
