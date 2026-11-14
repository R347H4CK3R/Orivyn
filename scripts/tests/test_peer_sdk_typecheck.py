import os
from pathlib import Path
import subprocess
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[2]

class PeerSDKTypecheckTests(unittest.TestCase):
    def run_gate(self, failure=''):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sdk = root / 'sdk'; sdk.mkdir()
            mock = root / 'xcrun'
            mock.write_text('''#!/bin/bash
set -eu
if [[ "$*" == '--sdk iphonesimulator --show-sdk-path' ]]; then
  [[ "${FAILURE:-}" != sdk ]] || { echo SDK-unavailable >&2; exit 21; }
  echo "$MOCK_SDK"
elif [[ "$*" == '--find swiftc' ]]; then
  [[ "${FAILURE:-}" != missing-compiler ]] || exit 22
  echo /mock/swiftc
elif [[ "$1" == swiftc ]]; then
  printf '%s\\n' "$@" > "$MOCK_ARGS"
  [[ "${FAILURE:-}" != compile ]] || { echo compiler-rejected >&2; exit 23; }
else exit 24; fi
''')
            mock.chmod(0o755)
            evidence = root / 'evidence'
            result = subprocess.run(['bash', str(ROOT / 'scripts/typecheck_peer_tls.sh'), str(evidence)],
                env={**os.environ, 'PATH': str(root)+os.pathsep+os.environ['PATH'], 'MOCK_SDK':str(sdk),
                     'MOCK_ARGS':str(root/'args'), 'FAILURE':failure}, capture_output=True, text=True)
            log=(evidence/'compiler.log').read_text()
            args=(root/'args').read_text() if (root/'args').exists() else ''
            admission=(evidence/'PeerTypecheckAdmission.swift').read_text() if (evidence/'PeerTypecheckAdmission.swift').exists() else ''
            return result.returncode, log, args, admission

    def test_compile_only_strict_flags_and_nonempty_admission(self):
        code, log, args, admission = self.run_gate()
        self.assertEqual(code, 0, log)
        for argument in ('-typecheck', '-swift-version\n6', '-strict-concurrency=complete', '-DORIVYN_PEER_TLS_SPIKE', '-target\narm64-apple-ios26.0-simulator', 'PeerTLSProbe.swift', 'PeerSyncControlFrame.swift'):
            self.assertIn(argument,args)
        self.assertIn('RequiredPeerProbe = PeerTLSProbe',admission)
        self.assertIn('import Security',admission)
        self.assertNotIn('simctl',args)
        self.assertIn("iOS: '26.0'", (ROOT/'project.yml').read_text())

    def test_missing_sdk_or_compiler_and_compilation_fail_closed(self):
        for failure, expected in [('sdk',21),('missing-compiler',22),('compile',23)]:
            with self.subTest(failure=failure):
                code,log,args,_=self.run_gate(failure)
                self.assertEqual(code,expected)
                self.assertNotIn('typecheck passed',log)
                if failure != 'compile': self.assertEqual(args,'')
                else: self.assertIn('compiler-rejected',log)

    def test_only_core_or_local_all_invoke_gate(self):
        source=(ROOT/'scripts/ci_macos.sh').read_text()
        self.assertIn('if [[ "$NATIVE_TEST_GROUP" == core || "$NATIVE_TEST_GROUP" == all ]]; then\n  bash scripts/typecheck_peer_tls.sh',source)
        self.assertNotIn('ORIVYN_PEER_TLS_SPIKE',(ROOT/'project.yml').read_text())
