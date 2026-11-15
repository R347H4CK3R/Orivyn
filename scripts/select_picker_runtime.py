#!/usr/bin/env python3
"""Select only the validated iOS26.1 iPhone16Plus, never a device alias."""
import json
import re
import sys

RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-26-1"

def select(inventory):
    choices = [d for d in inventory.get("devices", {}).get(RUNTIME, [])
               if d.get("isAvailable") is True and d.get("name") == "iPhone 16 Plus"]
    if len(choices) != 1:
        raise ValueError("Require exactly one available iPhone16Plus on the pinned iOS26.1 runtime")
    uuid = choices[0].get("udid", "")
    if not isinstance(uuid, str) or not re.fullmatch(r"[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}", uuid):
        raise ValueError("An exact simulator UUID is required")
    return uuid

if __name__ == "__main__":
    with open(sys.argv[1]) as handle:
        print(select(json.load(handle)))
