#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
export HOMEBREW_NO_AUTO_UPDATE=1
if ! command -v xcodegen >/dev/null; then brew install xcodegen; fi
mkdir -p artifacts/native-capabilities
set +e
bash Diagnostics/VMProof/run_native.sh 2>&1 | tee artifacts/native-capabilities/bios.log
BIOS_STATUS=${PIPESTATUS[0]}
set -e
cp Diagnostics/VMProof/artifacts/simulators.json artifacts/native-capabilities/simulators.json
cp -R Diagnostics/VMProof/artifacts artifacts/native-capabilities/bios
set +e
bash scripts/run_self_knowledge_gate.sh 2>&1 | tee artifacts/native-capabilities/self-knowledge.log
KNOWLEDGE_STATUS=${PIPESTATUS[0]}
set -e
printf 'BIOS_STATUS=%s\nKNOWLEDGE_STATUS=%s\n' "$BIOS_STATUS" "$KNOWLEDGE_STATUS" | tee artifacts/native-capabilities/status.txt
bash scripts/run_native_tests.sh --bundle-evidence artifacts
(( BIOS_STATUS == 0 && KNOWLEDGE_STATUS == 0 ))
