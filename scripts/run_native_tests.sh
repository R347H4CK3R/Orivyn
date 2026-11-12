#!/bin/bash
# Preserve native-test failure while still exporting screenshots for diagnosis.
set -euo pipefail
# The outer build wrapper always creates small evidence downloads before exiting.
if [[ "${1:-}" == "--run-build" ]]; then
  ARTIFACT_ROOT="$2"
  shift 2
  set +e
  "$@"
  BUILD_STATUS=$?
  bash "$0" --bundle-evidence "$ARTIFACT_ROOT"
  EVIDENCE_STATUS=$?
  set -e
  if (( BUILD_STATUS != 0 )); then exit "$BUILD_STATUS"; fi
  exit "$EVIDENCE_STATUS"
fi

if [[ "${1:-}" == "--bundle-evidence" ]]; then
  python3 - "$2" <<'PY'
from pathlib import Path
import sys
import zipfile

root = Path(sys.argv[1])
if not root.is_dir() or root.is_symlink():
    raise ValueError("Artifact root must be a real directory")
runs = sorted(path for path in root.iterdir() if path.is_dir() and not path.is_symlink())
if not runs:
    raise ValueError("No artifact run directories were found")
target_bytes = 8 * 1024 * 1024

def bundle(run, label, files):
    # Only these generated archives are replaced; all original evidence is retained.
    for old in run.glob(f"{label}-evidence-[0-9][0-9][0-9].zip"):
        if old.is_file() and not old.is_symlink():
            old.unlink()
    groups, current, size = [], [], 0
    for path in files:
        length = path.stat().st_size
        if current and size + length > target_bytes:
            groups.append(current)
            current, size = [], 0
        current.append(path)
        size += length
    if current:
        groups.append(current)
    for index, paths in enumerate(groups, 1):
        archive = run / f"{label}-evidence-{index:03d}.zip"
        if archive.is_symlink():
            raise ValueError("Refusing symbolic-link archive output")
        with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as zipped:
            for path in paths:
                zipped.write(path, path.relative_to(run))
        print(f"Evidence: {archive} ({archive.stat().st_size} bytes)")

for run in runs:
    logs = sorted(path for path in run.iterdir()
                  if path.is_file() and not path.is_symlink()
                  and (path.suffix.lower() in {".log", ".json", ".txt"} or path.name == "SHA256SUMS"))
    screenshots = run / "screenshots"
    images = sorted(path for path in screenshots.rglob("*")
                    if path.is_file() and not path.is_symlink()
                    and path.suffix.lower() in {".png", ".jpg", ".jpeg", ".json", ".txt"}) \
        if screenshots.is_dir() and not screenshots.is_symlink() else []
    bundle(run, "logs", logs)
    bundle(run, "screenshots", images)
PY
  exit $?
fi

ARTIFACTS="$1"
shift
set +e
"$@" 2>&1 | tee "$ARTIFACTS/native-tests.log"
TEST_STATUSES=("${PIPESTATUS[@]}")
set -e
if [[ -d "$ARTIFACTS/Tests.xcresult" ]]; then
  xcrun xcresulttool export attachments --path "$ARTIFACTS/Tests.xcresult" --output-path "$ARTIFACTS/screenshots" || true
fi
if (( TEST_STATUSES[0] != 0 )); then exit "${TEST_STATUSES[0]}"; fi
if (( TEST_STATUSES[1] != 0 )); then exit "${TEST_STATUSES[1]}"; fi
