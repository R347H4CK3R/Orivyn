"""Guard native fixture drift; Apple runtime tests are separately required."""
from pathlib import Path
import re
import unittest
ROOT = Path(__file__).resolve().parents[2]
class NativeFixtureContract(unittest.TestCase):
    def test_explicit_replace_and_default_preserve_coverage(self):
        source = (ROOT/'Tests/ImageAttachmentIntegrationTests.swift').read_text()
        case = source.split('func testHistoryMergeRemovesSupersededOriginalAndPreview()',1)[1].split('\n    func ',1)[0]
        self.assertIn('importHistory(from: backup, policy: .replaceMatching)', case)
        self.assertIn('func testDefaultHistoryMergePreservesLocalOriginalAndPreview()', source)
    def test_pinned_fixture_matches_materializer_and_bundle_contract(self):
        source = (ROOT/'Tests/VMPolicyTests.swift').read_text()
        materializer = (ROOT/'scripts/materialize_guest.py').read_text()
        digest = re.search(r"DISK_SHA = '([0-9a-f]{64})'", materializer)[1]
        first_case = source.split('func testOnlyPinnedGuestMayExceedSmallAssetLimit()',1)[1].split('\n    func ',1)[0]
        self.assertIn('sha256: "'+digest+'"', first_case)
        self.assertIn('appendingPathComponent("VMAssets"', source)
        self.assertNotIn('appendingPathComponent("Assets"', source)
        self.assertIn('func testObsoleteGuestPinIsRejected()', source)
if __name__ == '__main__': unittest.main()
