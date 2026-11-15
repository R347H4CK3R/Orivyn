#!/usr/bin/env python3
"""Exercise exact snapshot helper across process death with synthetic bytes only.
Never runs an iOS app or claims mmap/model inference verification.
"""
import argparse, json, pathlib, selectors, subprocess, tempfile

PROBE = '''import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
let root = URL(fileURLWithPath: CommandLine.arguments[2])
if CommandLine.arguments[1] == "hold" {
    let lease = try NativeModelSnapshot.create(in: root)
    try Data("synthetic model bytes".utf8).write(to: lease.modelURL)
    FileHandle.standardOutput.write(Data((lease.directory.path + "\\n").utf8))
    _ = withExtendedLifetime(lease) { sleep(120) }
} else {
    print(try NativeModelSnapshot.cleanup(in: root))
}
'''

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--swiftc', required=True)
    args = parser.parse_args()
    source = pathlib.Path(__file__).resolve().parents[1] / 'JarvisEVO/Core/NativeModelSnapshot.swift'
    with tempfile.TemporaryDirectory(prefix='orivyn-snapshot-process-') as temp:
        temp = pathlib.Path(temp)
        main = temp / 'main.swift'; main.write_text(PROBE)
        exe = temp / 'probe'
        subprocess.run([args.swiftc, str(source), str(main), '-o', str(exe)], check=True, timeout=120)
        root = temp / 'snapshots'; root.mkdir()
        child = subprocess.Popen([str(exe), 'hold', str(root)], stdout=subprocess.PIPE, text=True)
        try:
            with selectors.DefaultSelector() as wait:
                wait.register(child.stdout, selectors.EVENT_READ)
                assert wait.select(30), 'Child did not acquire a snapshot lease in time'
            directory = pathlib.Path(child.stdout.readline().strip())
            assert directory.parent == root and (directory / 'model.gguf').exists()
            active = subprocess.check_output([str(exe), 'cleanup', str(root)], text=True, timeout=10).strip()
            assert active == '0' and (directory / 'model.gguf').exists(), 'Active copy removed'
            child.kill(); child.wait(timeout=10)  # Only the synthetic child created here.
            stale = subprocess.check_output([str(exe), 'cleanup', str(root)], text=True, timeout=10).strip()
            assert stale == '1' and not directory.exists(), 'Crashed process copy not reclaimed'
            print(json.dumps({'active_other_process_preserved': True, 'terminated_child_orphan_reclaimed': True,
                              'scope': 'Host filesystem with synthetic bytes; not iOS inference'}))
        finally:
            if child.poll() is None:
                child.kill(); child.wait(timeout=10)

if __name__ == '__main__':
    main()
