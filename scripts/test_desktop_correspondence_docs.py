"""Checks current identity statements and historical boundary in desktop docs."""
import json, pathlib, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]

class DocumentationTests(unittest.TestCase):
    def test_native_gate_uses_verified_current_identity_before_history(self):
        text=(ROOT/'docs/verification/maintained-guest-native-gate.md').read_text()
        current=text.split('## Historical fixture')[0]
        self.assertIn('78418639ecd90573da211b62a502334f569f029b913525f50601b09d928b244d',current)
        self.assertNotIn('0897e5f867267c209f2866e2ee960971caf25886eb0345fe2f514b11e19cf0f1',current)
        self.assertIn('## Historical fixture',text)
    def test_audit_current_identity_matches_fresh_evidence(self):
        text=(ROOT/'ThirdPartyNotices/VirtualDesktop/UPSTREAM_AUDIT.md').read_text()
        self.assertIn('## Current maintained-guest candidate',text)
        current=text.split('## Historical prototype audit')[0]
        evidence=json.loads((ROOT/'docs/verification/desktop-source-correspondence.json').read_text())
        self.assertTrue(evidence['passed'])
        for asset in evidence['assets'].values(): self.assertIn(asset['sha256'],current)
        for key in ('guestSources','firmwareSources'):
            self.assertIn(evidence[key]['manifestSHA256'],current)
        self.assertIn('not license approval',current)
        self.assertIn('not physical-device verification',current)
    def test_historical_firmware_and_tinycore_audit_retained(self):
        text=(ROOT/'ThirdPartyNotices/VirtualDesktop/UPSTREAM_AUDIT.md').read_text()
        self.assertIn('Reproducible binary correspondence has not been independently rebuilt',text)
        self.assertIn('exclude from Orivyn source commits, IPA, distribution and public demos',text)

if __name__=='__main__': unittest.main()
