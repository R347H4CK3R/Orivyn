#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
node --test tests/*.test.cjs
python3 tests/check_assets.py
