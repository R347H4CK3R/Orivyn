# Automatic model and native tool implementation plan

Spec: docs/superpowers/specs/2026-11-12-automatic-model-tools-design.md

1. Author native UI acceptance tests for persisted Automatic mode, separate cellular permission and a typed Browser review card; run against absent controls to establish genuine RED. No fake production provider/result. Preserve exact source/log evidence.
2. Isolated pure worker: AutomaticModelRouter/NativeToolSuggestion plus unit tests. Bounded input, deterministic purpose/ranking, exact catalog descriptor matching, installed-only offline path, RAM/storage/network limits, conservative anchored tool intents. Production only after actual RED.
3. Integration owner: ModelDownloadPolicy and URLSession configuration; free-storage accessor and network snapshot; owner-tagged AppModel preparation tied to revisions, preserving manual provider choice and composer. Unit coverage for invalidation across awaits, repeat/cancel/new operation, manual download conflicts, failure and integrity rejection, no remote fallback or premature history mutation.
4. UI: Manual/Automatic controls with download policy explanation and explicit cellular option; visible decision/progress/Cancel; native action cards dispatch real review screens without losing draft. On background/navigation cancel preparation, not unrelated operations. Model prompt stays useful and honest.
5. Focused native GREEN: pure/coordinator/store tests and actual UI. Full aggregate source/native/UI/default-model and real general-to-coder switch/inference acceptance before package. Final review, screenshot inspection, ARM64/identity/license/privacy validation. Stage catalog before publication; retain previous verified release on failure.

Interfaces for pure worker:
- AutomaticRouteEnvironment(physicalMemory: UInt64, freeStorageBytes: Int64?, network: AutomaticDownloadNetwork, allowsCellular: Bool).
- AutomaticDownloadNetwork: unknown, offline, wifi, wired, cellular, constrained.
- AutomaticModelRouter.route(text: String, installed: [LocalModelDescriptor], environment: AutomaticRouteEnvironment) throws -> AutomaticModelDecision(model: LocalModelDescriptor, needsDownload: Bool, reason: String, purpose: String).
- NativeToolSuggestion.forText(String) -> optional enum email/calendar/browser/location/reminder, with id/title; suggestion only, never dispatch.
