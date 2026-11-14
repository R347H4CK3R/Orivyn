#!/usr/bin/env python3
"""Fail closed on missing, skipped, failed, or unexpected focused test counts."""
import json,sys
from pathlib import Path
summary=json.loads(Path(sys.argv[1]).read_text())
expected={'totalTestCount':39,'passedTests':39,'failedTests':0,'skippedTests':0}
for key,value in expected.items():
 if type(summary.get(key)) is not int or summary[key]!=value:
  raise SystemExit(f'Focused validation failed: {key} must be {value}, received {summary.get(key)!r}')
print('39 selected tests passed; focused regression only, not complete release acceptance.')
