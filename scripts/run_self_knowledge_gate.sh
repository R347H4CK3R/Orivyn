#!/usr/bin/env bash
 set -euo pipefail
 bash scripts/bootstrap_llama.sh
 python3 scripts/download_test_model.py
 python3 scripts/materialize_guest.py Fixtures/maintained.img.gz JarvisEVO/Resources/VMAssets/maintained.img
 python3 scripts/generate_project.py
 SIMULATOR_ID=$(python3 -c 'import json; v=json.load(open("artifacts/native-capabilities/simulators.json"))["devices"]; ds=[d for r,items in v.items() if "iOS-26" in r for d in items if "iPhone" in d["name"] and d.get("isAvailable")]; ds.sort(key=lambda d:(d["name"]!="iPhone 16 Plus",d["name"])); print(ds[0]["udid"])')
 xcodebuild -project JarvisEVO.xcodeproj -scheme JarvisEVO -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -parallel-testing-enabled NO -resultBundlePath artifacts/native-capabilities/SelfKnowledge.xcresult -only-testing:JarvisEVOTests/AppSelfKnowledgeTests -only-testing:JarvisEVOTests/AppModelTests CODE_SIGNING_ALLOWED=NO test
