# Isolated combined foreground sync candidate

Combines pairing/provisioning 9c48926e, scheduler/transport 479d98a2, app/session wiring 01318592 and history-import navigation f00d9145 on main development 6d73114f. Source syntax parsed on Swift 6 Linux; this is not Apple typechecking. Native gate compiles real iOS device/simulator with ORIVYN_PEER_TLS_SPIKE and executes eleven history-owner plus four negative permission/session tests. Zero skips required. Positive session end-to-end pairing and physical-device behavior remain unverified. Separate provisioned-Keychain mutual TLS and transport gates must pass before readiness.

Normal shipping project flags remain unchanged. Do not publish this as finished automatic sync. Trust is explicitly reviewed and session-local, never restored or enabled on launch. Pairing requires manual document exchange; foreground/protected-data availability gates the lifecycle. Existing model/vision limitations remain.
