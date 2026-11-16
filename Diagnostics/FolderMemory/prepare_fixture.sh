#!/bin/bash
# Provision a separate synthetic provider app only on this disposable CI simulator.
set -euo pipefail
: "${FOLDER_MEMORY_SIMULATOR:?}" "${RUNNER_TEMP:?}"
test "${GITHUB_ACTIONS:-}" = true
cd "$(dirname "$0")/../.."
(cd Diagnostics/FolderMemory && xcodegen generate --spec project.yml)
DERIVED="$RUNNER_TEMP/orivyn-memory-provider-fixture"
xcodebuild build -project Diagnostics/FolderMemory/MemoryFixture.xcodeproj -scheme MemoryFixture \
 -destination "platform=iOS Simulator,id=$FOLDER_MEMORY_SIMULATOR" -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO
xcrun simctl install "$FOLDER_MEMORY_SIMULATOR" "$DERIVED/Build/Products/Debug-iphonesimulator/MemoryFixture.app"
CONTAINER=$(xcrun simctl get_app_container "$FOLDER_MEMORY_SIMULATOR" app.orivyn.folder-import-fixture data)
mkdir -p "$CONTAINER/Documents/Memory Import Fixture"
printf '%s\n' 'Synthetic acceptance fact: Cedar trains are preferred.' > "$CONTAINER/Documents/Memory Import Fixture/notes.txt"
xcrun simctl launch "$FOLDER_MEMORY_SIMULATOR" app.orivyn.folder-import-fixture
