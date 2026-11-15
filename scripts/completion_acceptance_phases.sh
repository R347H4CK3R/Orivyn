#!/bin/bash
# Sourced after run_ui/run_real_model are defined. Each is fail-fast in its
# own subshell; do NOT use `if run_ui` or `run_ui || ...`, which disables
# errexit inside Bash functions and could mask an earlier required check.
set +e
(set -e; run_ui)
ui_status=$?
(set -e; run_real_model)
model_status=$?
set -e
printf 'ui=%s\nreal_model=%s\n' "$ui_status" "$model_status" > "$OUT/phase-status.txt"
test "$ui_status" = 0 && test "$model_status" = 0
