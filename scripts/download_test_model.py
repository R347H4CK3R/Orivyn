#!/usr/bin/env python3
"""Download the pinned public Apache-2.0 test model. No account or API key.

Prints the absolute verified file path on stdout. Progress/status goes to stderr.
"""
from __future__ import annotations
import argparse
import hashlib
from pathlib import Path
import sys
import urllib.request

URL = "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/9217f5db79a29953eb74d5343926648285ec7e67/qwen2.5-0.5b-instruct-q4_k_m.gguf"
SHA256 = "74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db"
SIZE = 491_400_032

def verify(path: Path) -> None:
    if path.stat().st_size != SIZE:
        raise ValueError("Model size mismatch; refusing test model")
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    if digest.hexdigest() != SHA256:
        raise ValueError("Model SHA-256 mismatch; refusing test model")

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1] / ".cache/test-models/qwen2.5-0.5b-instruct-q4_k_m.gguf")
    args = parser.parse_args()
    target = args.output.resolve()
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        verify(target)
    else:
        partial = target.with_suffix(".partial")
        try:
            print("Downloading 491 MB public test model...", file=sys.stderr)
            with urllib.request.urlopen(URL, timeout=120) as response, partial.open("wb") as out:
                if response.status != 200 or not response.url.startswith("https://"):
                    raise ValueError("Model download returned an invalid response")
                count = 0
                for chunk in iter(lambda: response.read(1024 * 1024), b""):
                    count += len(chunk)
                    if count > SIZE:
                        raise ValueError("Oversized model download rejected")
                    out.write(chunk)
            verify(partial)
            partial.replace(target)
        finally:
            partial.unlink(missing_ok=True)
    print(str(target))

if __name__ == "__main__":
    main()
