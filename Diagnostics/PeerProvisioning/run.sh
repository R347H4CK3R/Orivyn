#!/usr/bin/env bash
set -euo pipefail
umask 077
root="$(pwd)"
build_root="$(mktemp -d "$RUNNER_TEMP/orivyn-provisioning.XXXXXX")"
trap 'rm -rf "$build_root"' EXIT
# Diagnose the exact storage primitive before expensive X509 compilation.
# These private keys exist only as disposable CI fixtures and are never uploaded.
openssl_bin="$(brew --prefix openssl@3)/bin/openssl"
for mode in baseline updated; do
  "$openssl_bin" req -new -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -noenc \
    -keyout "$build_root/$mode.key" -out "$build_root/$mode.pem" \
    -subj "/CN=Orivyn-storage-fixture-$(uuidgen)" -days 1 \
    > /dev/null 2>&1
  "$openssl_bin" x509 -in "$build_root/$mode.pem" -outform DER -out "$build_root/$mode.der"
done
xcrun swiftc -g -swift-version 6 -parse-as-library Diagnostics/PeerProvisioning/check_certificate_storage.swift -o "$build_root/storage-probe"
xcrun lldb --batch -o run --one-line-on-crash "thread backtrace all" -- \
  "$build_root/storage-probe" "$build_root/baseline.der" "$build_root/updated.der" "$build_root/storage-pass" \
  2>&1 | tee "$RUNNER_TEMP/peer-provisioning-storage.log"
test "$(cat "$build_root/storage-pass")" = PASS
for dependency in swift-certificates:8789d7e78f996d56272836c8bf3590c5bd9c9754 swift-crypto:9f96b82711cc4ce5816343c02eccd5ad907972d3 swift-asn1:12b0abc19498e562a8d97eebb67a11e9e6a255dd; do
  repo="${dependency%%:*}"
  revision="${dependency#*:}"
  git init "$build_root/$repo" >> "$RUNNER_TEMP/peer-provisioning-dependencies.log" 2>&1
  git -C "$build_root/$repo" remote add origin "https://github.com/apple/$repo.git"
  git -C "$build_root/$repo" fetch --depth 1 origin "$revision" >> "$RUNNER_TEMP/peer-provisioning-dependencies.log" 2>&1
  git -C "$build_root/$repo" checkout --detach FETCH_HEAD >> "$RUNNER_TEMP/peer-provisioning-dependencies.log" 2>&1
  test "$(git -C "$build_root/$repo" rev-parse HEAD)" = "$revision"
done
mkdir -p "$build_root/gate/Sources/PairingPolicy" "$build_root/gate/Tests/PairingPolicyTests"
cp JarvisEVO/Core/PeerSyncControlFrame.swift JarvisEVO/Services/PeerTLSProbe.swift JarvisEVO/Core/PeerPairingApproval.swift JarvisEVO/Services/PeerIdentityProvisioner.swift "$build_root/gate/Sources/PairingPolicy/"
cp Diagnostics/PeerProvisioning/PeerIdentityProvisionerTests.swift "$build_root/gate/Tests/PairingPolicyTests/"
cat > "$build_root/gate/Package.swift" <<'EOF'
// swift-tools-version:6.2
import PackageDescription
let package = Package(name:"PairingPolicy",platforms:[.macOS(.v15)],dependencies:[
.package(path:"../swift-certificates"),.package(path:"../swift-asn1")],
targets:[.target(name:"PairingPolicy",dependencies:[.product(name:"X509",package:"swift-certificates"),.product(name:"SwiftASN1",package:"swift-asn1")],swiftSettings:[.define("ORIVYN_PEER_TLS_SPIKE")]),
.testTarget(name:"PairingPolicyTests",dependencies:["PairingPolicy",.product(name:"X509",package:"swift-certificates")])])
EOF
SWIFTCI_USE_LOCAL_DEPS=1 xcrun swift test --package-path "$build_root/gate" --jobs 2 2>&1 | tee "$RUNNER_TEMP/peer-provisioning-tests.log"
