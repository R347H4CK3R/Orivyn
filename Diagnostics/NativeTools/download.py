#!/usr/bin/env python3
"""Download the pinned public Apache-2.0 evaluation model. No account or API key.

Prints the absolute verified file path on stdout. Progress/status goes to stderr.
"""
from __future__ import annotations
import argparse
import hashlib
from pathlib import Path
import sys
import urllib.request

URL = "https://huggingface.co/Qwen/Qwen3-1.7B-GGUF/resolve/90862c4b9d2787eaed51d12237eafdfe7c5f6077/Qwen3-1.7B-Q8_0.gguf"
SHA256 = "061b54daade076b5d3362dac252678d17da8c68f07560be70818cace6590cb1a"
SIZE = 1834426016

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
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parent / "model.gguf")
    args = parser.parse_args()
    target = args.output.resolve()
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        verify(target)
    else:
        partial = target.with_suffix(".partial")
        try:
            print("Downloading 1835 MB public test model...", file=sys.stderr)
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
