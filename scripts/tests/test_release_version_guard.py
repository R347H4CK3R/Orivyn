import json
import pathlib
import plistlib
import subprocess
import sys
import tempfile
import unittest
import zipfile

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / 'release_version_guard.py'

class ReleaseVersionGuardTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = pathlib.Path(self.tmp.name)
        self.project = self.root / 'project.yml'
        (self.root / 'JarvisEVO').mkdir()
        self.source = self.root / 'source.json'
        self.write_project()
        self.feed = {'apps': [{'bundleIdentifier': 'app.jarvisevo.ios', 'versions': [
            {'version': '0.1.1', 'buildVersion': '17'},
            {'version': '0.1.0', 'buildVersion': '16'}]}]}
    def write_project(self, version='0.1.2', build='18', extra=''):
        self.project.write_text('settings:\n  base:\n    PRODUCT_BUNDLE_IDENTIFIER: app.jarvisevo.ios\n    MARKETING_VERSION: '+version+'\n    CURRENT_PROJECT_VERSION: '+build+'\n'+extra)
        (self.root / 'JarvisEVO' / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleShortVersionString':version.strip(chr(34)), 'CFBundleVersion':build.strip(chr(34)), 'OrivynReleaseNotes':'Current release notes.'}))
    def run_guard(self, ipa=None):
        self.source.write_text(json.dumps(self.feed))
        args = [sys.executable, str(SCRIPT), '--project', str(self.project), '--source', str(self.source)]
        if ipa: args += ['--ipa', str(ipa)]
        return subprocess.run(args, capture_output=True, text=True)
    def assert_rejected(self, ipa=None):
        result = self.run_guard(ipa)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('version guard:', result.stderr)
    def test_accepts_both_increasing(self):
        result=self.run_guard()
        self.assertEqual(result.returncode, 0, result.stderr)
    def test_rejects_build_only_increment(self):
        self.write_project(version='0.1.1'); self.assert_rejected()
    def test_rejects_marketing_only_increment(self):
        self.write_project(build='17'); self.assert_rejected()
    def test_checks_all_entries_not_only_first(self):
        self.feed['apps'][0]['versions'].append({'version':'0.1.3','buildVersion':'19'})
        self.assert_rejected()
    def test_rejects_missing_or_empty_matching_source(self):
        for apps in ([], [{'bundleIdentifier':'other','versions':[]}], [{'bundleIdentifier':'app.jarvisevo.ios','versions':[]}]):
            with self.subTest(apps=apps):
                self.feed={'apps':apps}; self.assert_rejected()
    def test_rejects_malformed_catalog(self):
        for feed in ([], {}, {'apps':None}, {'apps':[{'bundleIdentifier':'app.jarvisevo.ios','versions':[None]}]}):
            with self.subTest(feed=feed):
                self.feed=feed; self.assert_rejected()
    def test_rejects_duplicate_matching_apps(self):
        self.feed['apps'] *= 2; self.assert_rejected()
    def test_rejects_bad_versions(self):
        for version in ('0.1.2-beta','0.1.02','1.2','-1.2.3','1.2.3.4','"$(VERSION)"'):
            with self.subTest(version=version):
                self.write_project(version=version); self.assert_rejected()
    def test_rejects_bad_builds(self):
        for build in ('0','018','18-beta','10000','18.100','"$(BUILD)"'):
            with self.subTest(build=build):
                self.write_project(build=build); self.assert_rejected()
    def test_rejects_malformed_published_version(self):
        for record in ({'version':'0.1.1'}, {'version':'bad','buildVersion':'17'}, {'version':'0.1.1','buildVersion':17}):
            with self.subTest(record=record):
                self.feed['apps'][0]['versions']=[record]; self.assert_rejected()
    def test_rejects_project_override(self):
        self.write_project(extra='targets:\n  JarvisEVO:\n    settings:\n      MARKETING_VERSION: 0.1.1\n')
        self.assert_rejected()
    def test_numeric_comparison(self):
        self.write_project(version='0.1.10',build='20')
        self.feed['apps'][0]['versions']=[{'version':'0.1.9','buildVersion':'19'}]
        self.assertEqual(self.run_guard().returncode,0)
    def ipa(self, version='0.1.2', build='18', bundle='app.jarvisevo.ios', second=False, notes='Current release notes.'):
        path=self.root/'app.ipa'
        with zipfile.ZipFile(path,'w') as z:
            z.writestr('Payload/Orivyn.app/Info.plist',plistlib.dumps({'CFBundleShortVersionString':version,'CFBundleVersion':build,'CFBundleIdentifier':bundle,'OrivynReleaseNotes':notes}))
            if second: z.writestr('Payload/Other.app/Info.plist',plistlib.dumps({}))
        return path
    def test_source_plist_version_and_notes_required(self):
        p=self.root/'JarvisEVO'/'Info.plist'
        original=plistlib.loads(p.read_bytes())
        for changes in ({'CFBundleShortVersionString':'0.1.1'}, {'CFBundleVersion':'17'}, {'OrivynReleaseNotes':'   '}):
            with self.subTest(changes=changes):
                p.write_bytes(plistlib.dumps(dict(original,**changes))); self.assert_rejected()
    def test_ipa_matches_project(self):
        result=self.run_guard(self.ipa()); self.assertEqual(result.returncode,0,result.stderr)
    def test_ipa_rejects_version_build_identity_mismatch(self):
        for kwargs in ({'version':'0.1.1'},{'build':'17'},{'bundle':'other'},{'second':True},{'notes':'Stale notes.'}):
            with self.subTest(kwargs=kwargs): self.assert_rejected(self.ipa(**kwargs))

if __name__ == '__main__': unittest.main()
