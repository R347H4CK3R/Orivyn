#!/usr/bin/env python3
"""Validate an unsigned physical-device IPA. This does not prove runtime correctness or signing."""
import argparse
import hashlib
import json
import plistlib
import re
import stat
import struct
import unicodedata
import zipfile
from pathlib import Path, PurePosixPath

ARM64 = 0x0100000C
DEBUG_FIXTURE_MARKERS = (
    'RootViewRegressionFixture', 'RootViewFixtureProvider', 'root-ui-fixture',
    '--root-view-fixture', 'CONTROLLED ROOTVIEW FIXTURE',
    'beginControlledModelDownloadFixture',
)
CANDIDATE3_RESOURCES = {
    'katex-0.19.1.min.js': 'fa140498b8cfc8302cbe5e7cb1bdbc1f952bc38b3fa258ede09e73edbf9a74bc',
    'KaTeX-0.19.1-LICENSE.txt': '766ccc1f306c885aa45542a9846bbd0a505b27a0374f146778171c2254ce18e3',
}


def _release_content(archive, app, binary, build):
    # Inspect executable content, including literal and symbol encodings, rather
    # than treating a DEBUG source conditional as proof of Release exclusion.
    for marker in DEBUG_FIXTURE_MARKERS:
        if any(marker.encode(encoding) in binary for encoding in ('utf-8', 'utf-16-le', 'utf-16-be')):
            raise ValueError('DEBUG fixture marker remains in Release executable: ' + marker)
    # Supported shipping CFBundleVersion: one to three ASCII numeric components,
    # major 1...9999, optional minor/patch 0...99, canonical without leading zeroes.
    # Development suffixes and malformed numeric forms cannot select an older gate.
    if not isinstance(build, str) or re.fullmatch(r'[1-9][0-9]{0,3}(?:\.(?:0|[1-9][0-9]?)){0,2}', build) is None:
        raise ValueError('Invalid app build number; cannot select required resource checks')
    required = int(build.split('.')[0]) >= 3
    for item in archive.infolist():
        if not item.filename.startswith(app) or item.is_dir():
            continue
        relative = item.filename[len(app):]
        if PurePosixPath(relative).name.casefold() == 'ocr-card.png':
            raise ValueError('Test-only photo fixture is bundled in shipping app: ' + relative)
        with archive.open(item) as stream:
            prefix = stream.read(4)
        if relative.casefold().endswith('.gguf') or prefix == b'GGUF':
            raise ValueError('Bundled GGUF weights are not permitted in shipping app: ' + relative)
    resources = {}
    # Numeric build 3 introduced the renderer. Keep historical build 1/2 package
    # reverification usable, while making this gate automatic in unchanged CI.
    if required:
        expected_resources = dict(CANDIDATE3_RESOURCES)
        # Build 5 makes the runtime notice part of every app copy, not only source.
        if int(build.split('.')[0]) >= 5:
            expected_resources['llama.cpp-LICENSE.txt'] = '94f29bbed6a22c35b992c5c6ebf0e7c92f13b836b90f36f461c9cf2f0f1d010d'
        for name, expected in expected_resources.items():
            try:
                with archive.open(app + name) as stream:
                    digest = hashlib.file_digest(stream, 'sha256').hexdigest()
            except KeyError:
                raise ValueError('Missing required bundled resource: ' + name) from None
            if digest != expected:
                raise ValueError('Bundled resource SHA-256 mismatch: ' + name)
            resources[name] = digest
    return required, resources

def _macho(data, *, executable):
    if len(data) < 32:
        raise ValueError('Missing or truncated Mach-O binary')
    magic, cpu, _, kind, ncmds, sizeofcmds, _, _ = struct.unpack_from('<8I', data)
    if magic != 0xFEEDFACF or cpu != ARM64:
        raise ValueError('Expected a thin ARM64 Mach-O binary')
    if executable and kind != 2:
        raise ValueError('App binary is not MH_EXECUTE')
    if not executable and kind != 6:
        raise ValueError('Framework binary is not MH_DYLIB')
    if 32 + sizeofcmds > len(data) or ncmds > 4096:
        raise ValueError('Malformed Mach-O load commands')
    position, minimum, platform = 32, None, None
    dependencies = []
    for _ in range(ncmds):
        if position + 8 > 32 + sizeofcmds: raise ValueError('Truncated load command')
        command, size = struct.unpack_from('<II', data, position)
        if size < 8 or position + size > 32 + sizeofcmds: raise ValueError('Invalid load command size')
        if command == 0x32:
            if size < 24: raise ValueError('Invalid build version command')
            platform, minimum = struct.unpack_from('<II', data, position + 8)
        elif command == 0x25:
            if size < 16: raise ValueError('Invalid iOS version command')
            platform, minimum = 2, struct.unpack_from('<I', data, position + 8)[0]
        elif command in (0xC, 0x18 | 0x80000000, 0x1F | 0x80000000, 0x23 | 0x80000000):
            if size < 24: raise ValueError('Invalid dylib command')
            offset = struct.unpack_from('<I', data, position + 8)[0]
            if offset < 24 or offset >= size: raise ValueError('Invalid dylib string offset')
            dependencies.append(data[position + offset:position + size].split(b'\0',1)[0].decode('utf-8'))
        elif command in (0x21, 0x2C):
            if size < 20 or struct.unpack_from('<I', data, position + 16)[0] != 0:
                raise ValueError('Encrypted executable cannot be sideloaded')
        position += size
    if platform != 2 or minimum is None:
        raise ValueError('Binary is not built for physical iOS devices')
    if executable and minimum < 26 << 16:
        raise ValueError('App deployment target must be iOS 26 or newer')
    return minimum, dependencies

def verify(path):
    path = Path(path)
    with zipfile.ZipFile(path) as archive:
        entries = archive.infolist()
        names = [item.filename for item in entries]
        if len(names) != len(set(names)): raise ValueError('Duplicate archive paths')
        if len(names) > 100_000 or sum(item.file_size for item in entries) > 2_000_000_000:
            raise ValueError('Archive exceeds validation limits')
        canonical_names = set()
        for item in entries:
            name = item.filename
            raw_parts = name.removesuffix('/').split('/')
            if any(part in ('', '.', '..') for part in raw_parts):
                raise ValueError('Noncanonical archive path')
            canonical = unicodedata.normalize('NFC', name.removesuffix('/')).casefold()
            if canonical in canonical_names:
                raise ValueError('Archive path collision')
            canonical_names.add(canonical)
            parts = PurePosixPath(name).parts
            if name.startswith('/') or '\\' in name or '..' in parts or '\x00' in name:
                raise ValueError('Unsafe archive path')
            if stat.S_ISLNK(item.external_attr >> 16): raise ValueError('Symlinks are not permitted in this iOS package')
        apps = {name.split('/')[1] for name in names if name.startswith('Payload/') and len(name.split('/')) >= 3 and name.split('/')[1].endswith('.app')}
        if len(apps) != 1: raise ValueError('Expected exactly one Payload/App.app bundle')
        app = 'Payload/' + apps.pop() + '/'
        try: info = plistlib.loads(archive.read(app + 'Info.plist'))
        except (KeyError, plistlib.InvalidFileException): raise ValueError('Missing or invalid Info.plist') from None
        if info.get('CFBundleIdentifier') != 'app.jarvisevo.ios': raise ValueError('Unexpected app identifier')
        if info.get('CFBundleSupportedPlatforms') != ['iPhoneOS']: raise ValueError('Not an iPhoneOS build')
        executable = info.get('CFBundleExecutable','')
        if not executable or '/' in executable or '\\' in executable: raise ValueError('Invalid executable name')
        binary_path = app + executable
        if binary_path not in names: raise ValueError('Executable is missing')
        if app + 'Assets.car' not in names: raise ValueError('Compiled app assets are missing')
        binary = archive.read(binary_path)
        minimum, dependencies = _macho(binary, executable=True)
        minimum_text = f'{minimum >> 16}.{(minimum >> 8) & 255}'
        if str(info.get('MinimumOSVersion')) != minimum_text: raise ValueError('Plist and executable deployment targets differ')
        verified = set()
        pending = list(dependencies)
        while pending:
            dependency = pending.pop()
            if dependency.startswith(('/System/Library/','/usr/lib/')): continue
            if not dependency.startswith(('@rpath/', '@executable_path/Frameworks/')):
                raise ValueError('Unsupported non-system dependency: ' + dependency)
            relative = dependency.removeprefix('@rpath/').removeprefix('@executable_path/Frameworks/')
            if '..' in PurePosixPath(relative).parts: raise ValueError('Unsafe dependency path')
            framework = app + 'Frameworks/' + relative
            if framework in verified: continue
            if framework not in names: raise ValueError('Missing required framework: ' + relative)
            framework_minimum, nested = _macho(archive.read(framework), executable=False)
            if framework_minimum > minimum:
                raise ValueError('Framework requires a newer iOS than the app declares')
            verified.add(framework)
            pending.extend(nested)
        version, build = info.get('CFBundleShortVersionString'), info.get('CFBundleVersion')
        if not version or not build: raise ValueError('Missing app version')
        resources_required, resources = _release_content(archive, app, binary, build)
        with path.open('rb') as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        display_name = info.get('CFBundleDisplayName', 'Jarvis-EVO')
        if display_name not in ('Jarvis-EVO', 'Orivyn'): raise ValueError('Unsupported app display name')
        return {'app':display_name,'bundle_identifier':info['CFBundleIdentifier'],'version':version,'build':build,
                'architecture':'arm64','minimum_ios':minimum_text,'frameworks':sorted(verified),
                'sha256':digest,'size':path.stat().st_size,
                'release_fixture_markers_absent':True,'candidate3_resources_required':resources_required,
                'bundled_resources':resources,'bundled_test_media_absent':True,
                'verification':'package structure, executable fixture exclusion and build-specific resources only; runtime and SideStore signing are separate gates'}

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('ipa')
    parser.add_argument('--output')
    args = parser.parse_args()
    result = json.dumps(verify(args.ipa), indent=2)
    if args.output: Path(args.output).write_text(result + '\n')
    print(result)
