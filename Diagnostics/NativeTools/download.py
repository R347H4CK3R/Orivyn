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

DEFAULT_MODEL_ID = "qwen3-1.7b-q8_0"
MODELS = {'qwen3-1.7b-q8_0': {'fileName': 'Qwen3-1.7B-Q8_0.gguf', 'sha256': '061b54daade076b5d3362dac252678d17da8c68f07560be70818cace6590cb1a', 'byteCount': 1834426016, 'downloadURL': 'https://huggingface.co/Qwen/Qwen3-1.7B-GGUF/resolve/90862c4b9d2787eaed51d12237eafdfe7c5f6077/Qwen3-1.7B-Q8_0.gguf'}, 'qwen3-1.7b-q4_k_m': {'fileName': 'Qwen3-1.7B-Q4_K_M.gguf', 'sha256': 'd2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5', 'byteCount': 1282439264, 'downloadURL': 'https://huggingface.co/ggml-org/Qwen3-1.7B-GGUF/resolve/daeb8e2d528a760970442092f6bf1e55c3b659eb/Qwen3-1.7B-Q4_K_M.gguf'}}
URL = MODELS[DEFAULT_MODEL_ID]['downloadURL']
SHA256 = MODELS[DEFAULT_MODEL_ID]['sha256']
SIZE = MODELS[DEFAULT_MODEL_ID]['byteCount']

def select(model_id: str):
    if model_id not in MODELS:
        raise ValueError("Unknown pinned native test model ID")
    return MODELS[model_id]

def verify(path: Path, model_id: str = DEFAULT_MODEL_ID) -> None:
    model = select(model_id)
    if path.stat().st_size != model['byteCount']:
        raise ValueError("Model size mismatch; refusing test model")
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    if digest.hexdigest() != model['sha256']:
        raise ValueError("Model SHA-256 mismatch; refusing test model")

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parent / "model.gguf")
    parser.add_argument("--model-id", choices=sorted(MODELS), default=DEFAULT_MODEL_ID)
    args = parser.parse_args()
    model = select(args.model_id)
    target = args.output.resolve()
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        verify(target, args.model_id)
    else:
        partial = target.with_suffix(".partial")
        try:
            print(f"Downloading pinned {args.model_id} ({model['byteCount']} bytes)...", file=sys.stderr)
            with urllib.request.urlopen(model['downloadURL'], timeout=120) as response, partial.open("wb") as out:
                if response.status != 200 or not response.url.startswith("https://"):
                    raise ValueError("Model download returned an invalid response")
                count = 0
                for chunk in iter(lambda: response.read(1024 * 1024), b""):
                    count += len(chunk)
                    if count > model['byteCount']:
                        raise ValueError("Oversized model download rejected")
                    out.write(chunk)
            verify(partial, args.model_id)
            partial.replace(target)
        finally:
            partial.unlink(missing_ok=True)
    print(str(target))

if __name__ == "__main__":
    main()
