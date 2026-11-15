#!/usr/bin/env python3
"""Deterministic class-level XCTest selection; no test methods are excluded."""
import re
import sys
from pathlib import Path

GROUPS = ("all", "core", "ui-0", "ui-1", "ui-2")
ROOT = Path(__file__).resolve().parents[1]


def ui_classes(directory):
    names = []
    for source in sorted(directory.rglob("*.swift")):
        text = source.read_text()
        found = re.findall(r"\bclass\s+(\w+)\s*:\s*XCTestCase\b", text)
        if re.search(r"\bfunc\s+test\w*\s*\(", text) and not found:
            raise ValueError(f"Unrecognized UI test class in {source.name}")
        names.extend(found)
    if not names or len(set(names)) != len(names):
        raise ValueError("UI test classes must be nonempty and uniquely named")
    return sorted(names)


def selection(group, directory=ROOT / "UITests"):
    if group not in GROUPS:
        raise ValueError(f"Unknown native test group: {group}; expected {', '.join(GROUPS)}")
    if group == "all":
        return []
    if group == "core":
        return ["-only-testing:JarvisEVOTests"]
    classes = ui_classes(directory)[int(group[-1])::3]
    if not classes:
        raise ValueError(f"UI group {group} cannot be empty")
    return [f"-only-testing:JarvisEVOUITests/{name}" for name in classes]


if __name__ == "__main__":
    try:
        if len(sys.argv) != 2:
            raise ValueError("usage: native_test_groups.py GROUP")
        print("\n".join(selection(sys.argv[1])))
    except ValueError as error:
        raise SystemExit(str(error))
