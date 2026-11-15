#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
evidence=artifacts/peer-app
mkdir -p "$evidence"
git rev-parse HEAD > "$evidence/source-commit.txt"
printf '%s\n' 'Compile-only isolated iOS app integration with peer SPI. No listeners, pairing, automatic sync, package or release publication. Vision/tools feature flags are not enabled in this gate.' > "$evidence/SCOPE.txt"
xcodebuild -version > "$evidence/xcode-version.txt"
bash scripts/bootstrap_llama.sh
python3 scripts/materialize_guest.py Fixtures/maintained.img.gz JarvisEVO/Resources/VMAssets/maintained.img
if ! command -v xcodegen >/dev/null; then brew install xcodegen; fi
xcodegen generate
for platform in iOS 'iOS Simulator'; do
  suffix=${platform// /-}
  xcodebuild -project JarvisEVO.xcodeproj -scheme JarvisEVO -destination "generic/platform=$platform" -derivedDataPath "$RUNNER_TEMP/orivyn-peer-app-build" CODE_SIGNING_ALLOWED=NO ORIVYN_NATIVE_FEATURES=ORIVYN_PEER_TLS_SPIKE build > "$evidence/build-$suffix.log" 2>&1
done
python3 - "$evidence" <<'PY'
import pathlib,json,sys
root=pathlib.Path('JarvisEVO.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved')
data=json.loads(root.read_text())
actual={p['identity']:p['state']['revision'] for p in data['pins']}
expected={'swift-certificates':'8789d7e78f996d56272836c8bf3590c5bd9c9754','swift-asn1':'12b0abc19498e562a8d97eebb67a11e9e6a255dd','swift-crypto':'9f96b82711cc4ce5816343c02eccd5ad907972d3'}
assert all(actual.get(k)==v for k,v in expected.items()),actual
pathlib.Path(sys.argv[1],'Package.resolved').write_text(root.read_text())
pathlib.Path(sys.argv[1],'result.json').write_text(json.dumps({'deviceBuild':True,'simulatorBuild':True,'runtimeTests':False,'dependencies':actual},indent=2)+'\n')
PY
