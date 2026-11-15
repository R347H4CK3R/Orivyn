# Authenticated busy response verification — 2026-11-15

Production increment: dd327749d167a0e10124f61fc1094fbfa959d636.
Additional native rejection cases: 0645638ac1f1302aa2fb0b27502060e1ad98a84e.

The busy packet is a non-acknowledgement. Its canonical payload is exactly four UTF-8 bytes, "busy". The sender must match the exact staged transfer identity (both certificate pins, pairing generation, destination epoch and transfer UUID) and request digest before reporting typed peerBusy. No delivery receipt, ancestry update, replacement transfer, or successful delivery is recorded.

The busy responder validates the authenticated request, approved IDs, current destination epoch and persisted revocation status before sending. AppModel must invoke it only for admission busy before its receive operation has started consuming the request. An operation failure after consumption must not send a second response.

## Executed portable gate

GitHub Actions run https://github.com/R347H4CK3R/Orivyn/actions/runs/43682793657
Source dd327749d167a0e10124f61fc1094fbfa959d636, job 132716830389.

Swift 6.1.3 on Linux, production persistence and packet code using system SQLite: 141 tests passed, zero failures. This includes 12 packet tests, including two new busy-packet tests. These cover exact request binding retained by parsing, inability to interpret busy as a receipt, malformed/noncanonical payloads, extra fields and trailing bytes.

Portable tests do not verify TLS authentication, Network.framework behavior, iOS runtime, or physical devices.

## Added native gates awaiting the combined run

- Real authenticated receiver busy once, then delivery using the same durable pending transfer ID and exact payload; busy must leave delivered false.
- Forged busy digest, transfer, epoch and malformed payload must fail, not become retryable peerBusy.
- Busy responder must reject unapproved source, wrong epoch, revoked pairing and wrong request digest without importing or acknowledging.
- Existing authentication, receipt, cancellation, idle renewal and local busy gates remain required.

The production SPI remains gated. Native compilation/execution and actual AppModel ownership integration must pass separately before activation.
