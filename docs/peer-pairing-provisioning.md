# Explicit peer pairing and identity provisioning

This slice is experimental and does not enable ORIVYN_PEER_TLS_SPIKE in shipping builds.

## Trust flow

1. Explicit setup calls PeerIdentityProvisioner.loadOrCreate. It creates a P-256 SecKey in this device's Keychain and a self-signed non-CA certificate with digitalSignature and both client/server TLS usage. Private key bytes are never exported by this implementation.
2. Share only PeerPairingOffer, which contains certificate DER, shared pairing generation, optional destination epoch, and bounded proposed conversation metadata. Offers are untrusted and are not consent.
3. Both devices must use the same pairing generation. The initiator exports its generation; the responder imports it and creates its response using that generation.
4. Review full SHA-256 certificate fingerprints through each device's trusted display, separately from the imported offer. PeerPairingReviewView requires the complete 64-character fingerprint and explicit conversation selection; source IDs are displayed alongside titles.
5. PeerPairingCoordinator grants an immutable approval bound to local and remote certificate hashes, generation, receiver epoch, exact source IDs, and a fresh consent revision. No network payload or Codable approval can restore authority.
6. Receiving uses the local database epoch. Sending uses the intended receiver's epoch. These values cannot be reused blindly in both directions.
7. Before using the approval, the owner must construct PeerTLSProbePair from the actual SecIdentity and remote DER, check the durable database revocation state, and preserve all existing transaction/receipt/conflict checks.

The metadata in an offer is not authenticated merely because its certificate fingerprint matches. Titles and IDs must be treated as proposals and compared on the other device; the authenticated transfer and database remain independent gates.

## Lifecycle obligations of the integration owner

- Cancel and drain network work on lock, background, disabled sync, scope change, revocation, and identity reset.
- Revoke the database peer generation durably before deleting/replacing identity material.
- Drop in-memory approval immediately even if persistence fails. Do not restart while revocation persistence is unresolved.
- PeerPairingCoordinator.revoke retires the active/pending generation in memory; the database owns durable revocation across launches.
- No approval persistence is introduced here. Relaunch requires explicit reapproval until a separately reviewed protected consent store exists.
- A partial or expired Keychain identity fails closed; loadOrCreate never silently rotates it.
- Identity certificates last 30 days. Explicit reset and new verification are required after expiry.
- The view calls cancel on disappearance, including successful dismissal. Supply cancelReview, not a callback that revokes accepted authority.

## Verification scope

The policy harness tests rejection of wrong fingerprints, missing/invalid scope, self-pairing, replayed revoked generations, replacement without revocation, identity changes, malformed/bounded offers, duplicate IDs, control-character/oversize titles, and legacy metadata omission.

The native provisioning harness creates and reloads actual Keychain identities, checks their X.509 profile, signs and verifies a message using the actual private key, deletes/recreates identities, rejects silent renewal after expiry, and attempts mutual TLS between two generated identities on macOS loopback.

Initial test-only commit 64ff4f1fd67c9fef6fb339540a0c691b6ed252ef failed run 43679452772 because the new implementation file did not exist. This is a missing-implementation baseline, not a runtime assertion failure. Subsequent outcomes must be recorded from completed runs; pending CI is not acceptance.

The supplied UI has not been interacted with on iOS. Mac Keychain and loopback results do not establish iPhone Keychain lock behavior, Local Network consent, physical-device interoperability, persistent pairing recovery, or background execution.
