#!/usr/bin/env python3
"""Reject missing, skipped, failed or zero-test production gate results."""
import json
import pathlib
import sys


def verify(summary):
    expected = {'totalTestCount': 1, 'passedTests': 1, 'failedTests': 0, 'skippedTests': 0}
    for key, value in expected.items():
        if type(summary.get(key)) is not int or summary[key] != value:
            raise ValueError(f'Production gate requires {key}={value}; got {summary.get(key)!r}')


if __name__ == '__main__':
    verify(json.loads(pathlib.Path(sys.argv[1]).read_text()))
    print('One required production simulator test passed without skips; device acceptance remains separate.')
