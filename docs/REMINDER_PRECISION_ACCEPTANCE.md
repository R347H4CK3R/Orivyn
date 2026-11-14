# Reminder date precision and scheduler acceptance

Actual Foundation date conversion reproduced a confirmation defect: a subsecond Date can lose about0.000000119 seconds when stored as a Unix timestamp and reconstructed. The scheduler compares the full retained reminder, so a successful queued request could incorrectly report notScheduled. The exact scheduler host test reproduced this with unchanged ID/title/notes and a notification boundary that roundtrips dates exactly like the OS payload.

Validated reminders now retain the actual whole-second fire time. Rounding is upward; an explicit Date comparison prevents epoch conversion from rounding a near-ULP fraction backward before the ceil operation. Both the requested delay and final trigger delay must remain within5seconds–365days. No fuzzy equality or identity-only confirmation is introduced. Legacy fractional payload trigger components now round in the reference-date epoch to avoid the same earlier-trigger edge. New native payload regressions are added but not run.

The host runner extracts the actual scheduler and Foundation-only date-components method unchanged, recording their hashes.13checks pass: permission refusal, confirmed create, ambiguous retained add, owned/global capacity, permission-delay expiry, confirmed/refused cancellation, concurrent busy protection, Unix timestamp confirmation, and legacy fractional trigger precision. Notification APIs are explicit controlled boundaries: no real OS delivery, UserNotifications implementation, full SwiftUI or iPhone verification is claimed.

312 Foundation XCTest,135 Python,74 agent Node and39 VM Node tests pass. Fractional-precision red failures remain preserved in the evidence directories. Native UI/device and full-release requirements remain outstanding.

Private checkpoint09561e0e95e7016f3a1f3d2d897654415015d14b exact core source verified. No release or catalog changes.
