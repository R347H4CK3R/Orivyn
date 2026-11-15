# Pinned command compatibility

The first Linux run timed out before recording a decision. Pinned b9049 tools/cli/cli.cpp explicitly reports that --no-conversation is unsupported and asks for llama-completion; it then continues into conversational setup. Use the non-conversational completion target.

The pinned common/arg.cpp registers --no-show-timings only for the conversational CLI, so remove that flag for completion. It also processes prompt escapes by default. Pass --no-escape so serialized nested JSON remains byte-for-byte the supplied prompt in both comparison arms, and --simple-io for the subprocess. These are harness corrections, not app prompt changes or relaxed acceptance.

Timeouts preserve partial stdout/stderr with exit 124 and remain failures. All four arms are attempted and recorded; failures are never reported as useful model decisions.
