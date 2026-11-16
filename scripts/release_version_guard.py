#!/usr/bin/env python3
"""Fail closed unless both Orivyn release numbers exceed every published version."""
import argparse
import json
import plistlib
import re
import sys
import zipfile
from pathlib import Path

BUNDLE = 'app.jarvisevo.ios'


def marketing(value):
    if not isinstance(value, str) or re.fullmatch(r'(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)', value) is None:
        raise ValueError('marketing version must be canonical major.minor.patch')
    return tuple(map(int, value.split('.')))


def build_number(value):
    if not isinstance(value, str) or re.fullmatch(r'[1-9][0-9]{0,3}(?:\.(?:0|[1-9][0-9]?)){0,2}', value) is None:
        raise ValueError('build version must be a canonical Apple numeric build')
    parts = tuple(map(int, value.split('.')))
    return parts + (0,) * (3 - len(parts))


def project_versions(path):
    text = Path(path).read_text()
    # This repository uses XcodeGen's settings.base. Fail closed on overrides,
    # substitutions or duplicate declarations rather than partially parsing YAML.
    result = []
    for key in ('MARKETING_VERSION', 'CURRENT_PROJECT_VERSION'):
        all_values = re.findall(r'^\s*' + key + r'\s*:\s*(.*?)\s*$', text, re.M)
        base_values = re.findall(r'^    ' + key + r':\s*(.*?)\s*$', text, re.M)
        if len(all_values) != 1 or all_values != base_values:
            raise ValueError(f'{key} must have one unambiguous settings.base declaration')
        value = all_values[0]
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        result.append(value)
    marketing(result[0]); build_number(result[1])
    return tuple(result)


def verify(project, source, ipa=None):
    version, build = project_versions(project)
    info_path = Path(project).parent / 'JarvisEVO' / 'Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    if info.get('CFBundleShortVersionString') != version or info.get('CFBundleVersion') != build:
        raise ValueError('source Info.plist version/build must match project.yml')
    notes = info.get('OrivynReleaseNotes')
    if not isinstance(notes, str) or not notes.strip():
        raise ValueError('source Info.plist requires nonempty OrivynReleaseNotes')
    feed = json.loads(Path(source).read_text())
    if not isinstance(feed, dict) or not isinstance(feed.get('apps'), list):
        raise ValueError('catalog requires an apps array')
    apps = [app for app in feed['apps'] if isinstance(app, dict) and app.get('bundleIdentifier') == BUNDLE]
    if len(apps) != 1:
        raise ValueError('catalog must contain exactly one Orivyn application')
    versions = apps[0].get('versions')
    if not isinstance(versions, list) or not versions:
        raise ValueError('catalog requires nonempty published versions')
    for previous in versions:
        if not isinstance(previous, dict):
            raise ValueError('published version must be an object')
        old_version = marketing(previous.get('version'))
        old_build = build_number(previous.get('buildVersion'))
        if marketing(version) <= old_version or build_number(build) <= old_build:
            raise ValueError('both marketing version and build must exceed EVERY published version')
    if ipa:
        with zipfile.ZipFile(ipa) as archive:
            entries = [entry for entry in archive.infolist() if re.fullmatch(r'Payload/[^/]+\.app/Info\.plist', entry.filename)]
            if len(entries) != 1:
                raise ValueError('IPA requires exactly one top-level application Info.plist')
            packaged = plistlib.loads(archive.read(entries[0]))
        expected = {'CFBundleShortVersionString': version, 'CFBundleVersion': build,
                    'CFBundleIdentifier': BUNDLE, 'OrivynReleaseNotes': notes}
        if any(packaged.get(key) != value for key, value in expected.items()):
            raise ValueError('IPA identity, version, build and release notes must match source')
    return version, build


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', required=True)
    parser.add_argument('--source', required=True)
    parser.add_argument('--ipa')
    args = parser.parse_args()
    try:
        version, build = verify(args.project, args.source, args.ipa)
    except (OSError, ValueError, TypeError, KeyError, plistlib.InvalidFileException, zipfile.BadZipFile) as error:
        print(f'version guard: {error}', file=sys.stderr)
        return 1
    print(f'version guard: Orivyn {version} ({build}) exceeds all published versions; metadata matches')
    return 0


if __name__ == '__main__':
    sys.exit(main())
