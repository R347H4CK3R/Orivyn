#!/usr/bin/env python3
"""Explicit CI setup only: download the pinned production pair, never user images."""
import hashlib
import json
import shutil
import sys
import time
import urllib.request
from pathlib import Path
from verify_pair import verify_file


def main():
    if len(sys.argv) != 2:
        raise SystemExit('usage: prepare_production_pair.py DEDICATED_MODEL_DIRECTORY')
    target = Path(sys.argv[1]).absolute()
    if target.is_symlink():
        raise ValueError('Refusing symlink model directory')
    target.mkdir(mode=0o700, parents=True, exist_ok=True)
    manifest = json.loads((Path(__file__).parent / 'PRODUCTION_MODEL_PAIR.json').read_text())
    assets = manifest['artifacts']
    if len(assets) != 2 or sum(a['size'] for a in assets) > 2_000_000_000:
        raise ValueError('Pinned pair exceeds fixed asset budget')
    deadline = time.monotonic() + 900
    for asset in assets:
        name, size, expected = asset['file'], asset['size'], asset['sha']
        if Path(name).name != name or not name.endswith('.gguf'):
            raise ValueError('Invalid pinned filename')
        destination = target / name
        if destination.exists() or destination.is_symlink():
            verify_file(destination, size, expected)
            print('Verified existing', name, flush=True)
            continue
        if shutil.disk_usage(target).free < size * 2 + 512 * 1024 * 1024:
            raise ValueError('Insufficient free space for bounded fixture download')
        partial = target / (name + '.partial')
        created = False
        digest = hashlib.sha256(); count = 0
        url = f'https://huggingface.co/{manifest["repository"]}/resolve/{manifest["revision"]}/{name}'
        try:
            with partial.open('xb') as output:
                created = True
                with urllib.request.urlopen(url, timeout=60) as response:
                    if response.status != 200 or not response.url.startswith('https://'):
                        raise ValueError('Unexpected asset response')
                    while chunk := response.read(1024 * 1024):
                        count += len(chunk)
                        if count > size or time.monotonic() > deadline:
                            raise ValueError('Fixture download budget exceeded')
                        digest.update(chunk); output.write(chunk)
            if count != size or digest.hexdigest() != expected:
                raise ValueError('Fixture size/hash mismatch')
            partial.replace(destination)
            verify_file(destination, size, expected)
            print('Verified downloaded', name, size, flush=True)
        finally:
            if created:
                partial.unlink(missing_ok=True)
    shutil.copy2(Path(__file__).parent / 'PRODUCTION_MODEL_PAIR.json', target / 'MODEL_PAIR.json')
    print('Verified production pair; no app or simulator was launched.', flush=True)


if __name__ == '__main__':
    main()
