#!/usr/bin/env python3
"""Independently reject a zero subprocess exit without strict native evidence."""
import importlib.util
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('native_summary', ROOT / 'Diagnostics/NativeTools/verify_simulator_result.py')
summary_verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(summary_verifier)


def verify(directory):
    directory = Path(directory)
    summary_verifier.verify(json.loads((directory / 'test-summary.json').read_text()))
    bundle = directory / 'ProductionNativeTools.xcresult'
    info = bundle / 'Info.plist'
    if bundle.is_symlink() or not bundle.is_dir() or info.is_symlink() or not info.is_file():
        raise ValueError('Required native xcresult bundle and regular Info.plist are missing or symlinked')
    config = json.loads((directory / 'gate-config.json').read_text())
    expected = dict(gate='completion', modelID='qwen3-1.7b-q4_k_m',
                    selector='JarvisEVOTests/ProductionCompletionContractTests/testRequiredApprovedCallsBeforeGroundedAnswer')
    if not isinstance(config, dict) or any(config.get(key) != value for key, value in expected.items()):
        raise ValueError('Native gate configuration does not select the required completion test and model')
    lines = (directory / 'outcomes.txt').read_text().splitlines()
    required = {'xcodebuild=0', 'log=0', 'attachments=0', 'summary=0', 'verifier=0'}
    if len(lines) != len(required) or set(lines) != required:
        raise ValueError('Required native gate outcomes are missing, duplicated or nonzero')


if __name__ == '__main__':
    verify(sys.argv[1])
    print('Required native summary and all five subprocess outcomes verified.')
