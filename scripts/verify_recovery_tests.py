#!/usr/bin/env python3
"""Validate actual XCTest case result lines, not words inside test names."""
import pathlib,re,sys

def verify(text):
    results=re.findall(r"^Test Case .*' (passed|failed|skipped) [(]",text,re.M)
    if len(results)!=19 or any(value!='passed' for value in results):
        raise ValueError('Expected exactly 19 passed XCTest cases, no failed/skipped cases')
    if not re.search(r'Executed 19 tests, with 0 failures',text):
        raise ValueError('Missing expected XCTest summary')

if __name__=='__main__':
    verify(pathlib.Path(sys.argv[1]).read_text())
