#!/usr/bin/env python3
"""Bound simulator boot; recover once only on GitHub-hosted CI, never erase devices."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess


def boot(simulator, evidence, timeout=120, environment=None, run=subprocess.run):
    if not re.fullmatch(r'[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}', simulator):
        raise ValueError('An exact simulator UUID is required; aliases such as booted/all are forbidden')
    if type(timeout) is not int or not 1 <= timeout <= 300:
        raise ValueError('Boot timeout must be 1–300 seconds')
    environment = os.environ if environment is None else environment
    evidence = Path(evidence)
    evidence.parent.mkdir(parents=True, exist_ok=True)
    record = {'simulator': simulator, 'bootTimeoutSeconds': timeout, 'recoveryLimit': 1, 'steps': [], 'succeeded': False}

    def save():
        evidence.write_text(json.dumps(record, indent=2) + '\n')

    def command(arguments, seconds):
        try:
            result = run(['xcrun', 'simctl', *arguments], timeout=seconds, capture_output=True, text=True, check=False)
            step = {'arguments': arguments, 'timeoutSeconds': seconds, 'exitCode': result.returncode,
                    'stdout': result.stdout, 'stderr': result.stderr, 'timedOut': False}
        except subprocess.TimeoutExpired as error:
            def text(value):
                return value.decode('utf-8', errors='replace') if isinstance(value, bytes) else value or ''
            step = {'arguments': arguments, 'timeoutSeconds': seconds, 'exitCode': None,
                    'stdout': text(error.stdout), 'stderr': text(error.stderr), 'timedOut': True}
        record['steps'].append(step); save()
        return step

    def validate_selected():
        result = command(['list', 'devices', 'available', '-j'], 30)
        if result['timedOut'] or result['exitCode'] != 0:
            raise RuntimeError('Cannot revalidate the selected simulator; no recovery attempted')
        devices = json.loads(result['stdout'])['devices']
        matches = [(runtime, device) for runtime, values in devices.items() for device in values
                   if device.get('udid', '').lower() == simulator.lower()]
        if len(matches) != 1:
            raise RuntimeError('Selected simulator is absent or ambiguous; no recovery attempted')
        runtime, device = matches[0]
        if 'iOS-26' not in runtime or not device.get('isAvailable') or not device.get('name', '').startswith('iPhone'):
            raise RuntimeError('Only the exact available iOS 26 iPhone simulator selected by CI is accepted')

    try:
        validate_selected()
        first = command(['bootstatus', simulator, '-b'], timeout)
        if not first['timedOut'] and first['exitCode'] == 0:
            record['succeeded'] = True; return
        if environment.get('GITHUB_ACTIONS') != 'true' or environment.get('RUNNER_ENVIRONMENT') != 'github-hosted':
            raise RuntimeError('Boot failed; automatic shutdown recovery is restricted to GitHub-hosted CI')
        validate_selected()  # Never act on a stale/removed or differently selected device.
        stopped = command(['shutdown', simulator], 30)
        if stopped['timedOut'] or stopped['exitCode'] != 0:
            raise RuntimeError('Targeted simulator shutdown failed; no further boot attempt')
        # bootstatus -b boots this same UUID if needed, then waits with a fresh bound.
        second = command(['bootstatus', simulator, '-b'], timeout)
        if second['timedOut'] or second['exitCode'] != 0:
            raise RuntimeError('Simulator boot failed after one bounded targeted recovery; inspect simulator-boot.json')
        record['succeeded'] = True
    except Exception as error:
        record['error'] = str(error)
        raise
    finally:
        save()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--simulator', required=True)
    parser.add_argument('--evidence', required=True, type=Path)
    parser.add_argument('--timeout', type=int, default=120)
    args = parser.parse_args()
    boot(args.simulator, args.evidence, args.timeout)
    print('Exact selected simulator booted; at most one bounded CI recovery was used.')
