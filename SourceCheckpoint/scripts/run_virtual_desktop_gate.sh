#!/usr/bin/env bash
# Explicit invocation only after adequate free macOS capacity is confirmed.
# Never enables billing, starts a cloud build, publishes, or changes version.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodebuild >/dev/null || { echo 'Native gate not run: Xcode 26+ required.' >&2; exit 2; }
command -v xcodegen >/dev/null || { echo 'Native gate not run: XcodeGen required.' >&2; exit 2; }
OUT="artifacts/virtual-desktop-$(date -u +%Y%m%dT%H%M%SZ)-$$"
mkdir -p "$OUT"
python3 scripts/materialize_guest.py Fixtures/maintained.img.gz JarvisEVO/Resources/VMAssets/maintained.img
node --test scripts/vm-tests/*.test.cjs
node --test scripts/agent-tests/*.test.cjs
python3 -m unittest discover -s scripts/tests -v 2>&1 | tee "$OUT/portable-tests.log"
bash scripts/bootstrap_llama.sh
python3 scripts/download_test_model.py > "$OUT/test-model-path.txt"
xcodegen generate
xcrun simctl list devices available -j > "$OUT/simulators.json"
SIMULATOR_ID=$(python3 - "$OUT/simulators.json" <<'PY'
import json,sys
items=json.load(open(sys.argv[1]))['devices']
choices=[d for runtime,ds in items.items() if 'iOS-26' in runtime for d in ds if d.get('isAvailable') and 'iPhone' in d['name']]
choices.sort(key=lambda d:(d['name']!='iPhone 16 Plus',d['name']))
if not choices: raise SystemExit('No available iOS26 iPhone simulator; tests not run.')
print(choices[0]['udid'])
PY
)
xcodebuild -project JarvisEVO.xcodeproj -scheme JarvisEVO \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -parallel-testing-enabled NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 240 -maximum-test-execution-time-allowance 300 \
  -resultBundlePath "$OUT/VirtualDesktop.xcresult" \
  -only-testing:JarvisEVOTests/RuntimeDiagnosticsTests \
  -only-testing:JarvisEVOTests/PersistenceTests \
  -only-testing:JarvisEVOTests/ProviderTests \
  -only-testing:JarvisEVOTests/VoiceServiceTests \
  -only-testing:JarvisEVOTests/VoiceConversationControllerTests \
  -only-testing:JarvisEVOTests/VoiceConversationSessionTests \
  -only-testing:JarvisEVOTests/VoiceAppModelTests \
  -only-testing:JarvisEVOUITests/RootViewOwnershipUITests \
  -only-testing:JarvisEVOTests/SourceRepairDraftCoreTests \
  -only-testing:JarvisEVOTests/RepositoryInspectionTests \
  -only-testing:JarvisEVOTests/RepositorySourceDiagnosticsTests \
  -only-testing:JarvisEVOTests/VerifiedLocalPlanCoreTests \
  -only-testing:JarvisEVOTests/LocalAgentCoreTests \
  -only-testing:JarvisEVOTests/AttachmentServiceTests \
  -only-testing:JarvisEVOTests/ImageAttachmentServiceTests \
  -only-testing:JarvisEVOTests/OCRLineEvidenceTests \
  -only-testing:JarvisEVOTests/PDFTextExtractorTests \
  -only-testing:JarvisEVOTests/ConversationBranchTests \
  -only-testing:JarvisEVOTests/ConversationMetadataTests \
  -only-testing:JarvisEVOTests/ConversationSearchTests \
  -only-testing:JarvisEVOTests/MemorySearchTests \
  -only-testing:JarvisEVOTests/AppModelTests/testMemorySaveReportsFailureAndStableIDRetryDoesNotDuplicate \
  -only-testing:JarvisEVOTests/LocalHeavyWorkTests \
  -only-testing:JarvisEVOTests/VMPolicyTests \
  -only-testing:JarvisEVOTests/VMCheckpointStoreTests \
  -only-testing:JarvisEVOTests/VMCheckpointBridgeTests \
  -only-testing:JarvisEVOTests/VMTeardownCoordinatorTests \
  -only-testing:JarvisEVOUITests/VerifiedLocalReadUITests \
  -only-testing:JarvisEVOUITests/LocalAgentIntegrationUITests \
  -only-testing:JarvisEVOUITests/VirtualDesktopIntegrationUITests \
  CODE_SIGNING_ALLOWED=NO test 2>&1 | tee "$OUT/native-tests.log"
