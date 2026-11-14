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
shasum -a 256 JarvisEVO/Services/PeerTLSProbe.swift JarvisEVO/Core/PeerSyncControlFrame.swift Diagnostics/PeerAuthentication/NativePeerGate.swift > "$evidence/source-sha256.txt"
xcrun swiftc -swift-version 6 -strict-concurrency=complete -DORIVYN_PEER_TLS_SPIKE \
  -target "$(uname -m)-apple-macosx15.0" \
  JarvisEVO/Core/PeerSyncControlFrame.swift JarvisEVO/Services/PeerTLSProbe.swift \
  Diagnostics/PeerAuthentication/NativePeerGate.swift -o "$evidence/native-peer-gate" \
  > "$evidence/compile.log" 2>&1
"$evidence/native-peer-gate" "$fixture_dir" "$evidence/results.json" > "$evidence/run.log" 2>&1
