#!/usr/bin/env bash
set -euo pipefail
umask 077
root="$(cd "$(dirname "$0")/../.." && pwd)"
evidence="${1:?dedicated evidence directory}"
mkdir -p "$evidence"
fixture_dir="$(mktemp -d "${RUNNER_TEMP:-/tmp}/orivyn-peer-fixtures.XXXXXX")"
trap 'rm -rf -- "$fixture_dir"' EXIT
openssl_bin="$(brew --prefix openssl@3)/bin/openssl"
"$openssl_bin" version > "$evidence/openssl.txt"
xcrun swiftc --version > "$evidence/swift.txt"
"$openssl_bin" rand -hex 32 > "$fixture_dir/passphrase.txt"
make_identity() {
  local name="$1";shift
  "$openssl_bin" req -new -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -noenc \
    -keyout "$fixture_dir/$name.key" -out "$fixture_dir/$name.pem" -subj "/CN=Orivyn-test-$name" \
    -addext "basicConstraints=critical,CA:FALSE" -addext "keyUsage=critical,digitalSignature" "$@" \
    >> "$evidence/fixture-generation.log" 2>&1
}
for name in a b c; do make_identity "$name" -days 1 -addext "extendedKeyUsage=serverAuth,clientAuth"; done
make_identity expired -not_before 20000101000000Z -not_after 20010101000000Z -addext "extendedKeyUsage=serverAuth,clientAuth"
make_identity future -not_before 20990101000000Z -not_after 21000101000000Z -addext "extendedKeyUsage=serverAuth,clientAuth"
make_identity wrong-usage -days 1 -addext "extendedKeyUsage=serverAuth"
make_identity critical -days 1 -addext "extendedKeyUsage=serverAuth,clientAuth" -addext "1.2.3.4=critical,DER:01:01:FF"
cp "$fixture_dir/b.key" "$fixture_dir/bad-signature.key"
"$openssl_bin" x509 -in "$fixture_dir/b.pem" -badsig -out "$fixture_dir/bad-signature.pem"
for name in a b c expired future wrong-usage critical bad-signature; do
  "$openssl_bin" x509 -in "$fixture_dir/$name.pem" -outform DER -out "$fixture_dir/$name.der"
  # Legacy PKCS12 container ciphers only for disposable test identities imported
  # into process memory. Never distributed or used by the application.
  "$openssl_bin" pkcs12 -export -inkey "$fixture_dir/$name.key" -in "$fixture_dir/$name.pem" \
    -out "$fixture_dir/$name.p12" -passout "file:$fixture_dir/passphrase.txt" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1
done
cd "$root"
shasum -a 256 JarvisEVO/Services/PeerTLSProbe.swift JarvisEVO/Core/PeerSyncControlFrame.swift Diagnostics/PeerAuthentication/NativePeerGate.swift Diagnostics/PeerAuthentication/NativeChannelChecks.swift > "$evidence/source-sha256.txt"

build_root="$(mktemp -d "${RUNNER_TEMP:-/tmp}/orivyn-peer-build.XXXXXX")"
trap 'rm -rf -- "$fixture_dir" "$build_root"' EXIT
for dependency in swift-certificates:8789d7e78f996d56272836c8bf3590c5bd9c9754 swift-crypto:9f96b82711cc4ce5816343c02eccd5ad907972d3 swift-asn1:12b0abc19498e562a8d97eebb67a11e9e6a255dd; do
  repo="${dependency%%:*}"
  revision="${dependency#*:}"
  git init "$build_root/$repo" >> "$evidence/dependencies.log" 2>&1
  git -C "$build_root/$repo" remote add origin "https://github.com/apple/$repo.git"
  git -C "$build_root/$repo" fetch --depth 1 origin "$revision" >> "$evidence/dependencies.log" 2>&1
  git -C "$build_root/$repo" checkout --detach FETCH_HEAD >> "$evidence/dependencies.log" 2>&1
  test "$(git -C "$build_root/$repo" rev-parse HEAD)" = "$revision"
  printf '%s %s\n' "$repo" "$revision" >> "$evidence/dependency-revisions.txt"
done
mkdir -p "$build_root/gate/Sources/NativePeerGate"
cp Diagnostics/PeerAuthentication/Package.swift "$build_root/gate/Package.swift"
cp JarvisEVO/Core/PeerSyncControlFrame.swift JarvisEVO/Services/PeerTLSProbe.swift Diagnostics/PeerAuthentication/NativePeerGate.swift Diagnostics/PeerAuthentication/NativeChannelChecks.swift "$build_root/gate/Sources/NativePeerGate/"
cp Diagnostics/PeerAuthentication/NativeTextExchangeChecks.swift "$build_root/gate/Sources/NativePeerGate/"
if [[ -f JarvisEVO/Services/PeerTextRevisionExchange.swift ]]; then
  cp JarvisEVO/Services/PeerTextRevisionExchange.swift "$build_root/gate/Sources/NativePeerGate/"
fi
python3 - "$build_root/gate" "$evidence" <<'PY'
import pathlib,runpy,shutil,sys,hashlib,json
gate=pathlib.Path(sys.argv[1]);evidence=pathlib.Path(sys.argv[2])
for source in runpy.run_path('scripts/run_persistence_tests.py')['SOURCES']:
    shutil.copy2(source,gate/'Sources/NativePeerGate'/pathlib.Path(source).name)
manifest={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (gate/'Sources/NativePeerGate').glob('*.swift')}
(evidence/'source-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
PY
git rev-parse HEAD > "$evidence/app-source-commit.txt"
SWIFTCI_USE_LOCAL_DEPS=1 xcrun swift build --package-path "$build_root/gate" --jobs 2 \
  > "$evidence/compile.log" 2>&1
"$build_root/gate/.build/debug/NativePeerGate" "$fixture_dir" "$evidence/results.json" > "$evidence/run.log" 2>&1
