# Foreground sync scheduler integration

The Foundation-only `ForegroundSyncCoordinator` runs one reviewed peer/scope at a time. It is not connected to the shipping app in this slice; the Network/Security TLS experiment remains gated.

## Required owner wiring

The app owns the coordinator for its lifetime and calls `update` with current enablement, active scene state, protected-data availability and an immutable authorization whenever any of those changes. Start with all conditions false. Supply nil authorization immediately on revocation. Scope, consent revision, certificate pins, pairing generation and receiver epoch are part of equality, so any change cancels the previous task before a replacement starts. Stop via `update(.init())` before releasing the owner.

Map the pairing controller's ApprovedPeerPairing fields one-for-one into Authorization. The coordinator validates basic pin/scope shape but cannot authenticate an authorization. Only explicit reviewed pairing may supply one. Never derive it from discovery.

The operation must recheck persistent pairing/revocation and the exact approved source IDs before staging, use the authenticated pinned channel, preserve durable transfer IDs for lost-receipt retry, retain AppModel's exclusive history ownership around receive, and revalidate the captured authority at the database commit. Do not replace a pending durable transfer with a new import on retry.

Map only temporary network availability failures to retryableFailure. Authentication, revocation, wrong epoch, invalid receipt, scope and conflict failures return blocked. A success means the bounded exchange completed, including its receipt processing. The operation must enforce its own transport deadline and cancel its channel in a task cancellation handler. An operation ignoring cancellation deliberately holds the scheduler slot; lifecycle churn cannot launch a concurrent transfer.

## Scheduling limits

Successful foreground exchanges wait 30 seconds. Consecutive temporary failures retry after 2, 5 and 15 seconds, then stop after the fourth attempt. Lifecycle pause/resume retains the exhausted authorization. Explicit user retry or a different reviewed authorization can restart. This is foreground scheduling only: no background entitlement, wakeup or lock-screen operation is claimed.

## Verification scope

Diagnostics/ForegroundSync/Checks.swift compiles the actual production coordinator with Swift 6 strict concurrency. A manually advanced clock and controlled operation test five eligibility rejections, five cancellation/drain transitions, periodic scheduling, bounded retry exhaustion and explicit retry, security failure blocking and clock failure blocking. The operation deliberately ignores cancellation until released to expose overlapping-start bugs.

These checks do not exercise Network.framework, TLS, pairing UI, persistence, iOS lifecycle delivery, simulator or physical devices. App integration must verify these separately before activation.
