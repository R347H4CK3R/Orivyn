# Resume ownership regression

Repeated Resume admitted two asynchronous engine runs because the paused state persisted until await returned. A rejected run also left a false paused state. Both were reproduced in failing controller tests before the fix. Resume now owns an explicit resuming transition and reports failed execution without admitting a checkpoint.

Portable validation: 33 JavaScript tests, 15 exact asset checks and 3 materializer tests passed. Native simulator and physical device regression remain pending. No IPA, production readiness or full 1.0 completion is claimed.
