#!/usr/bin/env bash
set -euo pipefail
SWIFTC="${1:?Swift 6 compiler}"; OUTPUT="${2:?output executable}"
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
# Static official libraries avoid the recovered Linux dynamic Observation link
# incompatibility. No source rewriting, mocks of Observation or runtime patches.
"$SWIFTC" -static-stdlib -swift-version 6 -strict-concurrency=complete \
 "$ROOT/JarvisEVO/Core/LocalHeavyWork.swift" "$ROOT/JarvisEVO/Core/VisionSession.swift" \
 "$ROOT/Diagnostics/VisionProof/Linux/session_checks.swift" -o "$OUTPUT"
"$OUTPUT"
