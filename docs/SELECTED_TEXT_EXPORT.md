# Selected text export

Settings → Export selected text lets the user choose completed conversations,
review an immutable snapshot, and save those same bytes through the system file
exporter. Archived conversations can be selected. The output is a version-1
conversation backup compatible with the existing explicit import policy chooser.
It is manual transfer, not automatic synchronization or peer authentication.

The read transaction selects only requested IDs. Missing records fail the whole
operation. It checks stored blob sizes before copying/decoding, limits the snapshot
to 100 conversations, 1,000 messages and 5,000,000 bytes, rejects attachments and
all non-complete message states, and exports no saved memories. It never silently
drops private attachment text while claiming a complete conversation export.
The snapshot includes conversation/message IDs, roles, dates, titles, archive flags,
completed message text, schema version and export time. Original files, preferences,
provider credentials and saved memories are not part of this format.

Preparing a snapshot makes no network request and writes no file. Changing history,
backgrounding or dismissing the screen cancels pending preparation and clears the
review. An already handed-off file-export document retains its reviewed bytes until
the system callback; later edits cannot change it. The app cannot retract a save
already accepted by the system or control a user-selected cloud Files destination.
Repeated conflicting manual imports can still create additional copies; this path
does not use the dormant peer-receive replay identity.

Eight new exact-source SQLite tests cover selective exclusion, immutable bytes after
edit/delete and import roundtrip, invalid/missing/oversized selection, attachments,
all unfinished states, message/byte limits, pre-cancellation/transaction recovery,
and archived records. Together with existing persistence/framing tests: 72 passed
on Linux using host SQLite. The initial red build failed because exportTextSnapshot
was absent. SwiftUI syntax parsing passed; native compilation/exporter behavior is
reserved for the newly authorized GitHub Mac run, not inferred from portable tests.

The owner made Orivyn public and authorized free GitHub Mac runners on 2026-11-14.
The branch workflow only runs its standard macos-15 job when the repository is
public. It builds the exact pinned combined runtime, enables both native feature
flags, runs the native suite, and packages development build 7. It does not publish
a release. Physical iPhone acceptance and automatic sync remain separate work.
