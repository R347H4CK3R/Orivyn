from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class RecoveryPreviewTests(unittest.TestCase):
 def test_gate_retains_exact_host_and_package_steps(self):
  base=(ROOT/'.github/workflows/snapshot-build12.yml').read_text()
  base=base.replace('Verify Orivyn build 12 snapshot preview','Verify Orivyn build 13 recovery preview').replace('ci/snapshot-build12-20261115','ci/recovery-build13-20261115').replace("['.github/workflows/snapshot-build12.yml']","['.github/workflows/recovery-build13.yml']").replace('group: snapshot-build12','group: recovery-build13').replace('Orivyn-build12-package-evidence','Orivyn-build13-package-evidence')
  start=base.index('      - name: Verify Darwin');end=base.index('      - name: Build and verify combined native runtime',start)
  host=(ROOT/'.github/workflows/model-recovery.yml').read_text()
  a=host.index('      - name: Run exact');b=host.index('      - uses: actions/upload-artifact',a)
  self.assertEqual((ROOT/'.github/workflows/recovery-build13.yml').read_text(),base[:start]+host[a:b]+base[end:])
if __name__=='__main__':unittest.main()
