#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
node --test tests/controller.test.cjs tests/bios.test.cjs
python3 tests/check_assets.py
