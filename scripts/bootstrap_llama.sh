#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="b9049"
EXPECTED="49c374bf78d98f53bfb3571b2285d315351ca6a5c1112191ae6f8b2616dec1d1"
URL="https://github.com/ggml-org/llama.cpp/releases/download/${VERSION}/llama-${VERSION}-xcframework.zip"
COMBINED=0
if [[ -n "${ORIVYN_COMBINED_RUNTIME_ARCHIVE:-}" ]]; then
  [[ -z "${LLAMA_ARCHIVE:-}" ]] || { echo "Choose one runtime archive." >&2; exit 1; }
  [[ "${ORIVYN_COMBINED_RUNTIME_SHA256:-}" =~ ^[a-f0-9]{64}$ ]] || { echo "Combined runtime requires its reviewed SHA-256." >&2; exit 1; }
  COMBINED=1
  VERSION="b9049-combined"
  EXPECTED="$ORIVYN_COMBINED_RUNTIME_SHA256"
  LLAMA_ARCHIVE="$ORIVYN_COMBINED_RUNTIME_ARCHIVE"
fi
CACHE="$ROOT/.cache"
DEST="$ROOT/Packages/LlamaRuntime/Frameworks"
mkdir -p "$CACHE" "$DEST"
# Optional offline cache path. It must match the same pinned checksum, never bypass it.
ARCHIVE="${LLAMA_ARCHIVE:-$CACHE/llama-${VERSION}-xcframework.zip}"
if [[ ! -f "$ARCHIVE" ]]; then
  [[ -z "${LLAMA_ARCHIVE:-}" ]] || { echo "Provided LLAMA_ARCHIVE does not exist." >&2; exit 1; }
  curl --fail --location --proto '=https' --proto-redir '=https' --retry 3 "$URL" -o "$ARCHIVE.partial"
  mv "$ARCHIVE.partial" "$ARCHIVE"
fi
if command -v shasum >/dev/null; then
  ACTUAL="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
else
  ACTUAL="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
fi
[[ "$ACTUAL" == "$EXPECTED" ]] || { echo "llama.cpp archive checksum mismatch. Refusing to extract or use it." >&2; exit 1; }
STAGE="$(mktemp -d "$DEST/.stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
unzip -q "$ARCHIVE" -d "$STAGE"
FRAMEWORK="$STAGE/build-apple/llama.xcframework"
if [[ "$COMBINED" == 1 ]]; then
  FRAMEWORK="$STAGE/llama.xcframework"
  python3 "$ROOT/scripts/verify_combined_runtime.py" "$FRAMEWORK"
fi
[[ -f "$FRAMEWORK/Info.plist" && -d "$FRAMEWORK/ios-arm64" && -d "$FRAMEWORK/ios-arm64_x86_64-simulator" ]] || { echo "Verified archive is missing required iOS device or simulator slices." >&2; exit 1; }
# Move any old generated dependency aside only after the new one passes all checks.
if [[ -e "$DEST/llama.xcframework" ]]; then mv "$DEST/llama.xcframework" "$STAGE/previous.xcframework"; fi
mv "$FRAMEWORK" "$DEST/llama.xcframework"
printf '%s\n' "$VERSION $EXPECTED" > "$DEST/verified-release.txt"
echo "Verified llama.cpp $VERSION installed with iOS device and simulator support."
