# Text transfer wire boundary

The strict packet parser at d172e689bb117ffdac21e43db70066243f165954 passed the portable production suite and all 139 production persistence tests, including ten packet regressions: https://github.com/R347H4CK3R/Orivyn/actions/runs/43664139592 . The preceding test-only commit failed because the packet API was absent: https://github.com/R347H4CK3R/Orivyn/actions/runs/43663760031 .

The format carries sender/receiver certificate hashes, pairing generation, receiver epoch, transfer ID and declared request SHA-256. A bounded length-prefixed canonical header is followed by the exact canonical revision envelope or canonical receipt summary. Unknown/duplicate/noncanonical header fields, wrong kinds, empty/oversized/truncated/trailing payloads, malformed scope fields and invalid receipt record shapes are rejected.

`UnverifiedTextRevisionPacket` is deliberately NOT an authentication or write capability. It checks digest length only, not digest correctness. Before sending or importing, a future live adapter must bind all identity fields to the actual retained authenticated channel, recompute SHA-256, verify immutable approved scope and lifecycle ownership, and use the store's atomic revocation/epoch/ancestry checks. The sender must accept only the matching request digest and receipt before advancing its durable state. No adapter, automatic scheduler, pairing UI, or database write path was enabled by this parser.

Native transport already passed eight authentication and seven channel cases, including an integration rerun at f8bd5c0: https://github.com/R347H4CK3R/Orivyn/actions/runs/43663363831 . This parser's new tests are portable Foundation/SQLite tests, not networked end-to-end sync or device acceptance.
