# Local live diagnostics

Settings → Privacy & capabilities → Live diagnostics now projects allowlisted real AppModel operational state: response-active flag and observed character count, automatic model preparation, reported download fraction, installed-model count, attachment import, image save, heavy-work ownership/phase, inference admission block, network path and current error-notification presence.

It samples immediately and every 30 seconds while the view is open and the app is active, plus explicit Refresh now. Only state changes append events; last-checked and last-change timestamps remain separate. At most 200 events are held in view-local memory. No prompt/reply text, file names, paths, conversation/model identifiers, endpoint addresses, API keys, arbitrary error descriptions, or source contents are recorded. No diagnostics export, upload or persistence is performed. Closing the screen discards its log.

The UI explicitly states unchanged values do not prove a stall, a ready lease does not prove runtime progress, and network path availability does not validate a remote provider. It does not claim a background monitor or continuous engine heartbeat. View-visible sampling alone cannot detect every operation between samples.

One native regression tests change-only records and 200-event bound; it is authored but uncompiled/unrun. One portable structural privacy/lifecycle guard failed before implementation then passed; full suites pass: 113 Python, 60 agent JavaScript, 39 VM JavaScript. Native UI/runtime/device acceptance still required; no paid CI, version change or publication.

Independent review follow-up: sampling is scene-phase gated and download percentage requires a current download owner, so queued stale progress cannot masquerade as an active transfer. Targeted structural guard passes after both changes.
