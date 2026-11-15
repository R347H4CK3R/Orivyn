# Empty output is not a decision

Run 43666978289 returned exit 0 in all four arms, but captured empty stdout/stderr. These are invalid observations, not passing model decisions. Pinned tools/completion/completion.cpp emits generated token text through LOG; --log-disable suppressed it. Remove that flag and retain raw streams. Require one parsed decision object per arm and permit only the completion tool's exact terminal [end of text] marker after it. Missing/malformed output fails the harness even when the process exits 0.

The application and native acceptance gates were not changed. The paired encoding hypothesis remains untested until valid decisions are captured.
