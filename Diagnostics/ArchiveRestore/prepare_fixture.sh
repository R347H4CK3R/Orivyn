#!/bin/bash
# Place only generated synthetic data in a separate disposable simulator app.
set -euo pipefail
: "${ARCHIVE_RESTORE_SIMULATOR:?}" "${RUNNER_TEMP:?}"
test "${GITHUB_ACTIONS:-}" = true
test "${RUNNER_ENVIRONMENT:-}" = github-hosted
cd "$(dirname "$0")/../.."
(cd Diagnostics/ArchiveRestore && xcodegen generate --spec project.yml)
DERIVED="$RUNNER_TEMP/orivyn-archive-provider-fixture"
xcodebuild build -project Diagnostics/ArchiveRestore/ArchiveFixture.xcodeproj -scheme ArchiveFixture \
 -destination "platform=iOS Simulator,id=$ARCHIVE_RESTORE_SIMULATOR" -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO
xcrun simctl install "$ARCHIVE_RESTORE_SIMULATOR" "$DERIVED/Build/Products/Debug-iphonesimulator/ArchiveFixture.app"
CONTAINER=$(xcrun simctl get_app_container "$ARCHIVE_RESTORE_SIMULATOR" app.orivyn.archive-import-fixture data)
mkdir -p "$CONTAINER/Documents"
# The generator uses exclusive creation. Existing fixture data is never overwritten.
python3 Diagnostics/ArchiveRestore/make_fixture.py "$CONTAINER/Documents/Synthetic ChatGPT Backup.zip"
xcrun simctl launch "$ARCHIVE_RESTORE_SIMULATOR" app.orivyn.archive-import-fixture
