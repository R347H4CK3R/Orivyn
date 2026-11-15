"""Shell control-flow tests only; mock phases do not establish native success."""
import itertools
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
COORDINATOR = ROOT / 'scripts/completion_acceptance_phases.sh'


class CompletionPhaseCoordinationTests(unittest.TestCase):
    def test_failure_combinations_are_independent_but_fail_closed(self):
        # A non-final failure must abort UI progression, not merely be masked
        # by a later successful command; real inference must still be attempted.
        for approval, relaunch, state, model in itertools.product((0, 7), repeat=4):
            with self.subTest(approval=approval, relaunch=relaunch, state=state, model=model), tempfile.TemporaryDirectory() as directory:
                out = pathlib.Path(directory)
                script = '''
set -euo pipefail
run_ui() {
 echo approval >> "$OUT/calls"
 (exit "$APPROVAL")
 echo relaunch >> "$OUT/calls"
 (exit "$RELAUNCH")
 echo state >> "$OUT/calls"
 (exit "$STATE")
}
run_real_model() {
 echo model >> "$OUT/calls"
 (exit "$MODEL")
 echo model-finished >> "$OUT/calls"
}
source "$COORDINATOR"
'''
                import os
                env = dict(os.environ, OUT=str(out), COORDINATOR=str(COORDINATOR), APPROVAL=str(approval), RELAUNCH=str(relaunch), STATE=str(state), MODEL=str(model))
                result = subprocess.run(['bash', '-c', script], env=env, capture_output=True, text=True)
                self.assertTrue((out / 'calls').exists(), result.stderr)
                expected = ['approval']
                if not approval:
                    expected.append('relaunch')
                    if not relaunch:
                        expected.append('state')
                expected.append('model')
                if not model:
                    expected.append('model-finished')
                self.assertEqual((out / 'calls').read_text().splitlines(), expected)
                ui = approval or relaunch or state
                self.assertEqual(result.returncode == 0, not (ui or model))
                self.assertEqual((out / 'phase-status.txt').read_text(), f'ui={ui}\nreal_model={model}\n')

    def test_main_wires_required_order_and_keeps_strict_checks(self):
        source = (ROOT / 'scripts/ci_completion_acceptance.sh').read_text()
        self.assertIn('run_ui() {', source)
        self.assertIn('run_real_model() {', source)
        self.assertIn('source scripts/completion_acceptance_phases.sh', source)
        self.assertLess(source.index('for PHASE in approval relaunch'), source.index('verify_completion_ui_state.py'))
        self.assertIn('verify_simulator_result.py', source)
        self.assertIn('test "$status" = 0', source)
        self.assertIn('-maximum-test-execution-time-allowance 600', source)
        self.assertIn('bash Diagnostics/NativeTools/run_production_simulator.sh', source)


if __name__ == '__main__':
    unittest.main()
