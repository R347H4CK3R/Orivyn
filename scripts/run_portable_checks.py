#!/usr/bin/env python3
"""Run local, non-Apple checks and retain logs plus an honest machine-readable summary.

No downloads, CI dispatch, external providers, signing, or publication. Swift must
already be installed. SQLite integration is optional and needs a local amalgamation.
Use a new output directory for each run; previous evidence is never overwritten.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time


def run_stage(name, command, root, output):
    started = time.monotonic()
    log_path = output / (name + '.log')
    result = {'name': name, 'command': command, 'log': log_path.name}
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1', ORIVYN_TEST_ARTIFACTS=str(output))
    try:
        with log_path.open('w') as log:
            process = subprocess.run(command, cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT)
        result.update(status='passed' if process.returncode == 0 else 'failed', exit_code=process.returncode)
    except OSError as error:
        log_path.write_text(str(error) + '\n')
        result.update(status='failed', exit_code=None, error=str(error))
    result['seconds'] = round(time.monotonic() - started, 3)
    return result


def source_manifest(root):
    # Include production and test inputs, not generated build directories or logs.
    paths = []
    for folder in ['JarvisEVO', 'Tests', 'scripts', 'Fixtures', 'Packages']:
        paths.extend((root / folder).rglob('*'))
    return [{'path': str(path.relative_to(root)), 'bytes': path.stat().st_size,
             'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
            for path in sorted(paths)
            if path.is_file() and not path.is_symlink()
            and not any(part in {'.build', '__pycache__', '.cache'} for part in path.parts)]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--swift', required=True, help='Installed Swift 6 executable')
    parser.add_argument('--node', default='node', help='Installed Node executable')
    parser.add_argument('--sqlite-source', type=Path, help='Optional directory containing sqlite3.c and sqlite3.h')
    parser.add_argument('--output', required=True, type=Path, help='New evidence directory outside the source tree')
    args = parser.parse_args(argv)
    root = Path(__file__).resolve().parents[1]
    output = args.output.resolve()
    if output == root or root in output.parents:
        parser.error('--output must be outside the source tree')
    if output.exists():
        parser.error('--output must be a new directory; existing evidence is preserved')
    if args.sqlite_source and not all((args.sqlite_source / name).is_file() for name in ['sqlite3.c', 'sqlite3.h']):
        parser.error('--sqlite-source must contain sqlite3.c and sqlite3.h')
    output.mkdir(parents=True)
    summary = {
        'started_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'scope': 'Portable checks only; no Apple SDK build, simulator, device, real provider, or release verification.',
        'source_manifest': 'SOURCE-MANIFEST.json',
        'known_exclusions': [
            'Python real-tokenizer test may skip without its explicit local dependencies; inspect python.log.',
            'Linux Foundation harness excludes the unsupported URLProtocol redirect fixture; inspect foundation.log.',
        ],
        'stages': [],
    }
    stages = [
        ('guest-fixture', [sys.executable, '-B', 'scripts/materialize_guest.py',
                           'Fixtures/maintained.img.gz', 'JarvisEVO/Resources/VMAssets/maintained.img']),
        ('python', [sys.executable, '-B', '-m', 'unittest', 'discover', '-s', 'scripts/tests', '-p', 'test_*.py']),
        ('catalog', [sys.executable, '-B', 'scripts/model_catalog.py', '--check']),
        ('agent', [args.node, '--test'] + [str(p.relative_to(root)) for p in sorted((root / 'scripts/agent-tests').glob('*.test.cjs'))]),
        ('vm', [args.node, '--test'] + [str(p.relative_to(root)) for p in sorted((root / 'scripts/vm-tests').glob('*.test.cjs'))]),
        ('foundation', [sys.executable, '-B', 'scripts/run_foundation_tests.py', '--swift', args.swift, '--output', str(output / 'foundation')]),
    ]
    if args.sqlite_source:
        stages.append(('persistence', [sys.executable, '-B', 'scripts/run_persistence_tests.py', '--swift', args.swift,
                                     '--sqlite-source', str(args.sqlite_source.resolve()), '--output', str(output / 'persistence')]))
    else:
        summary['stages'].append({'name': 'persistence', 'status': 'skipped',
                                  'reason': 'No local SQLite amalgamation supplied; this is not a persistence-test pass.'})
    def save():
        (output / 'SUMMARY.json').write_text(json.dumps(summary, indent=2) + '\n')
    save()
    try:
        for name, command in stages:
            print('Running ' + name + '...', flush=True)
            result = run_stage(name, command, root, output)
            summary['stages'].append(result)
            if name == 'guest-fixture':
                # Record the generated, checksum-verified guest that the tests read.
                (output / 'SOURCE-MANIFEST.json').write_text(json.dumps(source_manifest(root), indent=2) + '\n')
            save()
            print(name + ': ' + result['status'], flush=True)
    except KeyboardInterrupt:
        summary['status'] = 'interrupted'
        save()
        return 130
    summary['status'] = 'failed' if any(s['status'] == 'failed' for s in summary['stages']) else 'passed_with_exclusions'
    summary['finished_at'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    save()
    print(str(output / 'SUMMARY.json'))
    print(summary['scope'])
    return 1 if summary['status'] == 'failed' else 0


if __name__ == '__main__':
    raise SystemExit(main())
