#!/usr/bin/env python3
"""Generate the app graph; only explicit peer builds resolve peer packages."""
import argparse
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
PEER_FLAG = "ORIVYN_PEER_TLS_SPIKE"

def selected_spec(features, peer=False):
    return "project-peer.json" if peer or PEER_FLAG in features.split() else "project.yml"

def generate(features, peer=False):
    spec = selected_spec(features, peer)
    subprocess.run(["xcodegen", "generate", "--spec", spec], cwd=ROOT, check=True)
    return spec

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--peer", action="store_true",
                        help="Include exact pinned peer packages for the isolated SPI gate.")
    args = parser.parse_args()
    generate(os.environ.get("ORIVYN_NATIVE_FEATURES", ""), args.peer)

if __name__ == "__main__":
    main()
