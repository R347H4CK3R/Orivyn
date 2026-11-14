# Cross-device transfer and iCloud feasibility

## Implemented local foundation
Settings now offers **Add missing only (keep local)** before selecting a JSON backup. Under one immediate SQLite transaction, this mode preserves every existing conversation and memory identifier, adds only absent identifiers, validates image bindings against all retained rows, and reports written/skipped counts. Reimporting the same snapshot adds no duplicates. No device clock decides which version wins. Existing replacement import remains an explicit destructive choice; this is not message-level merge. The backup file stays intact, so skipped incoming records remain in the selected source.

AppModel defaults to preserve-local. The lower-level store retains its previous replace-matching default for existing callers/tests. Native regression covers preserved conflicting chat/memory, added new chat and repeat import. Native execution is unverified. Two portable source guards pass, with full suite 112 Python / 60 agent JS / 39 VM JS.

## CloudKit blocker verified from current source
`project.yml` builds unsigned and has no iCloud capability, container entitlement or development team. No provisioning profile supporting an app-owned iCloud container has been verified. Adding fabricated entitlement strings cannot provide that authorization and could break SideStore signing. No capability was enabled, account accessed, or cloud upload attempted.

Apple's CloudKit setup requires a supported developer team/membership, iCloud capability, registered container and matching signing configuration; test devices must be signed into iCloud. Source: https://developer.apple.com/documentation/cloudkit/enabling-cloudkit-in-your-app.md (read November 13, 2026).

Apple supports user-selected external files/directories through the document picker, including available iCloud/File Provider locations, with security-scoped access and file coordination. Source: https://developer.apple.com/documentation/uikit/providing-access-to-directories.md (read November 13, 2026). The existing JSON exporter/importer can be used with a location the user chooses, but provider availability, upload arrival and second-device import have not been tested. No background watcher/bookmark/folder sync has been implemented.

## Remaining executable gates
1. Confirm actual installation profile/team supports the intended registered iCloud container before introducing CloudKit entitlements.
2. Choose explicit private-cloud data scope and opt-in UI; never silently transmit conversation or memory content.
3. Implement durable per-record versions, tombstones and recoverable conflict copies; preserve-local import is a foundation, not synchronization.
4. Coordinate provider file reads and bound bytes while reading, not only by prior size metadata, before relying on external-file synchronization.
5. Test disconnection/retry, concurrent edits, account changes, deletion propagation and attachment asset integrity on two actual devices.

Automatic cross-device synchronization and native/device acceptance remain unfinished. No backend computer, paid CI, release or catalog modification occurred.
