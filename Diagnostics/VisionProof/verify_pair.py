#!/usr/bin/env python3
"""Development-only verifier. Never downloads, modifies or bundles model weights."""
import hashlib, json, os, pathlib, stat, sys

def verify_file(path, size, expected):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_size != size:
            raise ValueError('Not a regular exact-size model')
        digest = hashlib.sha256(); total = 0
        while True:
            data = os.read(fd, min(1024 * 1024, size + 1 - total))
            if not data: break
            total += len(data)
            if total > size: raise ValueError('Model grew')
            digest.update(data)
        if total != size or digest.hexdigest() != expected:
            raise ValueError('Model digest mismatch')
    finally: os.close(fd)

if __name__ == '__main__':
    if len(sys.argv) != 2: raise SystemExit('usage: verify_pair.py IMMUTABLE_MODEL_DIRECTORY')
    manifest = json.loads(pathlib.Path(__file__).with_name('MODEL_PAIR.json').read_text())
    for entry in manifest['artifacts']:
        verify_file(pathlib.Path(sys.argv[1]) / entry['file'], entry['size'], entry['actualSHA256'])
        print('Verified:', entry['file'])
