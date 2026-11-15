# Preserved native port fixture failure — 2026-11-15

Failing combined source: 76e0732d2941f82381480960dc95841fdd6581a1
Run: https://github.com/R347H4CK3R/Orivyn/actions/runs/43685006410
Artifact: 14150193092
Downloaded ZIP SHA-256: b998a7546bf6047c996dd5e8eeb0898baa09cf81fd8384ad83fb17b7c609ab7e

Independently downloaded and inspected in memory. The native run log contains only:
`Fatal error: Error raised at top level: NativePeerGate.GateError.failed("fixture listener failed")`.

Retained JSON results establish 38 passing checks: 8 authentication, 7 channel, 17 text-exchange and the first 6 automatic-sync cases. The process exited 133 before receiver-busy-once and accepted-incomplete-is-failure could produce results. Those two cases did not pass or complete. The underlying NWError was discarded by the fixture, so its exact cause is unproven.

The temporary free-port listener had no newConnectionHandler, unlike the production listener. The candidate repair configures a reject-all connection handler before start, retains the actual NWError in failure output, bounds readiness/cancellation to five seconds, and clears handlers during cleanup. The same fixture correction is applied to the actual-session XCTest. Production transport, authentication and acceptance checks are unchanged.

Apple describes canceling an incoming connection to reject it:
https://developer.apple.com/documentation/network/nwlistener/newconnectionhandler

This is a diagnostic repair awaiting the coordinated native rerun, not a claim that the underlying platform error has been reproduced or resolved.
