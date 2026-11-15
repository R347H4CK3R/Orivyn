"""Mock harness execution is not evidence of native inference success."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
GATE = ROOT / 'Diagnostics/NativeTools/run_production_simulator.sh'


class CompletionGateEvidenceTests(unittest.TestCase):
    def test_missing_or_failed_evidence_rejected(self):
        verifier = ROOT / 'scripts/verify_completion_model_evidence.py'
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            def run():
                return subprocess.run(['python3', str(verifier), d], capture_output=True).returncode
            self.assertNotEqual(run(), 0)
            (root/'test-summary.json').write_text(json.dumps(dict(totalTestCount=1, passedTests=1, failedTests=0, skippedTests=0)))
            self.assertNotEqual(run(), 0)
            good = 'xcodebuild=0\nlog=0\nattachments=0\nsummary=0\nverifier=0\n'
            (root/'outcomes.txt').write_text(good)
            self.assertNotEqual(run(), 0)
            bundle = root/'ProductionNativeTools.xcresult'
            bundle.mkdir()
            self.assertNotEqual(run(), 0)
            info = bundle/'Info.plist'
            info.write_text('mock bundle metadata, not native evidence')
            self.assertNotEqual(run(), 0)
            config = dict(gate='completion', modelID='qwen3-1.7b-q4_k_m', selector='JarvisEVOTests/ProductionCompletionContractTests/testRequiredApprovedCallsBeforeGroundedAnswer')
            (root/'gate-config.json').write_text(json.dumps(config))
            self.assertEqual(run(), 0)
            for key in config:
                wrong = dict(config); wrong[key] = 'wrong'
                (root/'gate-config.json').write_text(json.dumps(wrong))
                self.assertNotEqual(run(), 0)
            (root/'gate-config.json').write_text(json.dumps(config))
            info.unlink()
            target = root/'metadata'; target.write_text('mock')
            info.symlink_to(target)
            self.assertNotEqual(run(), 0)
            info.unlink(); info.write_text('mock')
            bundle.rename(root/'real-bundle')
            bundle.symlink_to(root/'real-bundle', target_is_directory=True)
            self.assertNotEqual(run(), 0)
            bundle.unlink(); (root/'real-bundle').rename(bundle)
            for content in [good.replace('xcodebuild=0','xcodebuild=1'), good+'verifier=0\n', good.replace('log=0\n',''), good+'other=0\n']:
                (root/'outcomes.txt').write_text(content)
                self.assertNotEqual(run(), 0)
            (root/'outcomes.txt').write_text(good)
            for counts in [dict(totalTestCount=0, passedTests=0, failedTests=0, skippedTests=0), dict(totalTestCount=1, passedTests=0, failedTests=0, skippedTests=1)]:
                (root/'test-summary.json').write_text(json.dumps(counts))
                self.assertNotEqual(run(), 0)

    def run_early_exit(self, injected, expected=None):
        # Exercise actual EXIT cleanup. Reproduce an early exit reporting zero;
        # the incomplete gate must never turn this into acceptance.
        with tempfile.TemporaryDirectory() as d:
            root=Path(d); scripts=root/'Diagnostics/NativeTools'; scripts.mkdir(parents=True)
            scheme=root/'JarvisEVO.xcodeproj/xcshareddata/xcschemes/JarvisEVO.xcscheme'
            scheme.parent.mkdir(parents=True); scheme.write_text('original')
            source=GATE.read_text()
            source=source.replace('# TestAction environment is explicit;', 'echo changed > "$SCHEME"\n'+injected+'\n# TestAction environment is explicit;',1)
            gate=scripts/'run.sh';gate.write_text(source)
            bins=root/'bin';bins.mkdir()
            for name, text in [('uname','echo Darwin'),('vm_stat','true')]:
                p=bins/name;p.write_text('#!/bin/bash\n'+text+'\n');p.chmod(0o755)
            env=dict(os.environ, PATH=str(bins)+':'+os.environ['PATH'], ORIVYN_NATIVE_TOOLS_MODEL_DIR=str(root/'model'),NATIVE_TOOLS_DESTINATION='platform=iOS Simulator,id=fake',NATIVE_TOOLS_DERIVED_DATA=str(root/'derived'),NATIVE_TOOLS_EVIDENCE_DIR=str(root/'evidence'),ORIVYN_NATIVE_FEATURES='ORIVYN_NATIVE_TOOLS')
            result=subprocess.run(['bash',str(gate)],env=env,capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0,result.stderr)
            if expected is not None:
                self.assertEqual(result.returncode,expected,result.stderr)
            self.assertEqual(scheme.read_text(),'original')

    def test_unexpected_early_success_is_failure_and_scheme_restored(self):
        self.run_early_exit('exit 0', 1)

    def test_nonzero_exit_preserved_and_scheme_restored(self):
        self.run_early_exit('exit 7', 7)

    def test_nounset_failure_is_nonzero_and_scheme_restored(self):
        self.run_early_exit('unset ORIVYN_MISSING_TEST_VARIABLE; : "$ORIVYN_MISSING_TEST_VARIABLE"')

    def test_optional_arguments_do_not_expand_empty_array(self):
        source=GATE.read_text()
        self.assertNotIn('${TRANSCRIPT_ARGS[@]}',source)
        self.assertIn('"$@" > "$NATIVE_TOOLS_EVIDENCE_DIR/gate-config.json"',source)

    def test_zero_exit_without_artifacts_cannot_pass_real_wrapper(self):
        source=(ROOT/'scripts/ci_completion_acceptance.sh').read_text()
        body=source.split('run_real_model() {',1)[1].split('\n}',1)[0]
        with tempfile.TemporaryDirectory() as d:
            root=Path(d); bins=root/'bin'; bins.mkdir()
            mock=bins/'bash'; mock.write_text('#!/bin/sh\nexit 0\n'); mock.chmod(0o755)
            env=dict(os.environ, PATH=str(bins)+':'+os.environ['PATH'], OUT=d, SIM='fake', DERIVED=str(root/'derived'), MODEL_DIR=str(root/'models'))
            result=subprocess.run(['/bin/bash','-c','set -euo pipefail\n'+body],cwd=ROOT,env=env,capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0,result.stderr)
            self.assertIn('test-summary.json',result.stderr)

    def test_wrapper_independently_verifies_evidence(self):
        source=(ROOT/'scripts/ci_completion_acceptance.sh').read_text()
        body=source.split('run_real_model() {',1)[1].split('\n}',1)[0]
        self.assertIn('python3 scripts/verify_completion_model_evidence.py "$NATIVE_TOOLS_EVIDENCE_DIR"',body)
        self.assertLess(body.index('run_production_simulator.sh'),body.index('verify_completion_model_evidence.py'))


if __name__ == '__main__':
    unittest.main()
