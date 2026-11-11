#!/usr/bin/env python3
"""Name a candidate from its built bundle metadata, never an untrusted path."""
import argparse
import plistlib
import re
from pathlib import Path


def candidate_filename(info_path):
    with Path(info_path).open("rb") as stream:
        info = plistlib.load(stream)
    versions = []
    for key in ("CFBundleShortVersionString", "CFBundleVersion"):
        value = info.get(key)
        if not isinstance(value, str) or re.fullmatch(r"[0-9]+(?:\.[0-9]+)*", value) is None:
            raise ValueError(f"{key} must contain only ASCII digits separated by single dots")
        versions.append(value)
    return f"Jarvis-EVO-{versions[0]}-build{versions[1]}-unsigned.ipa"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("info_plist")
    args = parser.parse_args()
    try:
        print(candidate_filename(args.info_plist))
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        parser.error(str(error))
