#!/bin/bash
# Compile-only SDK gate. Never starts a listener, connects, or enables app flags.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EVIDENCE="${1:?Provide an evidence directory}"
mkdir -p "$EVIDENCE"
EVIDENCE="$(cd "$EVIDENCE" && pwd)"
(
  SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
  [[ -d "$SDK" ]] || { echo 'Missing iOS simulator SDK directory' >&2; exit 2; }
  xcrun --find swiftc
  # Match the app deployment target; do not accidentally accept a dormant #if.
  cat > "$EVIDENCE/PeerTypecheckAdmission.swift" <<'SWIFT'
import Network
import Security
import CryptoKit
private typealias RequiredPeerProbe = PeerTLSProbe
private typealias RequiredPeerFrame = PeerSyncControlFrame
SWIFT
  xcrun swiftc -typecheck -swift-version 6 -strict-concurrency=complete \
    -DORIVYN_PEER_TLS_SPIKE -sdk "$SDK" -target arm64-apple-ios26.0-simulator \
    -module-cache-path "$EVIDENCE/module-cache" \
    "$ROOT/JarvisEVO/Core/PeerSyncControlFrame.swift" \
    "$ROOT/JarvisEVO/Services/PeerTLSProbe.swift" \
    "$EVIDENCE/PeerTypecheckAdmission.swift"
  echo 'Peer TLS standalone SDK typecheck passed; handshake/trust/device behavior remains unverified.'
) 2>&1 | tee "$EVIDENCE/compiler.log"
