#!/usr/bin/env python3
"""Require the complete native transport acceptance matrix, never partial output."""
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
expected = {
    "results.json": 8,
    "channel-results.json": 7,
    "text-exchange-results.json": 17,
    "automatic-sync-results.json": 8,
}
for name, count in expected.items():
    results = json.loads((root / name).read_text())
    assert isinstance(results, list) and len(results) == count, (name, len(results), count)
    assert len({row["name"] for row in results}) == count, (name, "duplicate case name")
    assert all(row["passed"] is True for row in results), (name, results)
print("All 40 actual native transport cases passed.")
