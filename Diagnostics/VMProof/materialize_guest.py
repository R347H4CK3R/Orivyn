"""Offline internal guest fixture staging; never fetches or publishes assets."""
from pathlib import Path
import argparse, gzip, hashlib, os, stat, tempfile
DISK_BYTES = 135266304
DISK_SHA = '0897e5f867267c209f2866e2ee960971caf25886eb0345fe2f514b11e19cf0f1'
ARCHIVE_SHA = 'e3f9b8a21f15d7dcfca9c30caeb268b7d443027ae46d2f2ecff260c4f91e8815'
ARCHIVE_LIMIT = 32 * 1024 * 1024

def materialize(source, destination):
    source, destination = Path(source), Path(destination)
    # Refuse links before opening; O_NOFOLLOW also closes the leaf race.
    if source.is_symlink() or destination.is_symlink():
        raise ValueError('Symlinks are not accepted')
    fd = os.open(source, os.O_RDONLY | os.O_NOFOLLOW)
    temporary = None
    try:
        with os.fdopen(fd, 'rb') as stream:
            info = os.fstat(stream.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_size > ARCHIVE_LIMIT:
                raise ValueError('Invalid archive type or size')
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
            if digest != ARCHIVE_SHA:
                raise ValueError('Archive checksum mismatch')
            stream.seek(0)
            with tempfile.NamedTemporaryFile(dir=destination.parent, prefix='.guest-', delete=False) as output:
                temporary = Path(output.name)
                checksum, count = hashlib.sha256(), 0
                with gzip.GzipFile(fileobj=stream) as archive:
                    while chunk := archive.read(1024 * 1024):
                        count += len(chunk)
                        if count > DISK_BYTES:
                            raise ValueError('Expanded guest exceeds pinned size')
                        checksum.update(chunk)
                        output.write(chunk)
                if count != DISK_BYTES or checksum.hexdigest() != DISK_SHA:
                    raise ValueError('Guest checksum or size mismatch')
                output.flush()
                os.fsync(output.fileno())
            os.replace(temporary, destination)
            temporary = None
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    materialize(args.archive, args.destination)
