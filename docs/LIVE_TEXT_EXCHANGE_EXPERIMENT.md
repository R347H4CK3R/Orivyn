# Experimental authenticated text exchange

This isolated branch connects the tested authenticated channel to durable text revision storage. It is disabled in the shipping application by ORIVYN_PEER_TLS_SPIKE.

Sender checks the immutable staged transfer against the actual channel's local/peer certificate fingerprints and pairing generation. It computes SHA-256 from the staged bytes and requires the receipt to bind that hash and complete transfer identity before recording delivery.

Receiver requires locally supplied approved conversation IDs and receiver epoch, verifies both channel fingerprints, generation and actual payload hash, and rejects out-of-scope source IDs before calling transactional storage. Storage independently checks revocation, current epoch, exact ancestry and conflicts. The receiver commits before acknowledging; failure to deliver a receipt must leave sender state pending.

Task cancellation closes the channel. Cancellation is not a replacement for persistent pairing revocation. Approved scope must come from a trusted local UI/controller, never the packet itself. This adapter does not provide remote attestation of durable writes.

Seven native loopback scenarios use two real SQLite stores: successful import/receipt, unapproved source, wrong epoch, revoked receiver, forged request digest, forged receipt digest and forged receipt transfer. Existing eight authentication and seven channel checks also remain required. The first test-only attempt failed at duplicate SQLite module setup; its corrected test-only run remains queued. This implementation has only passed Swift syntax parsing so far; no native exchange result is claimed.

Not implemented: certificate provisioning/pairing UI, consent lifecycle and unsaved-edit coordination, scheduling, device/network failure acceptance or background convergence. Lost-receipt/retry and mid-flight revocation regression coverage must precede application activation. Nothing here enables automatic sync or authorizes publishing.
