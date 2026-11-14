#!/usr/bin/env python3
"""Verify the opt-in locally built Apple runtime before replacing a dependency.
This checks packaging/ABI, not model quality, app execution or device acceptance.
"""
import pathlib, plistlib, re, subprocess, sys

REQUIRED = {'_llama_model_load_from_file', '_llama_init_from_model', '_llama_decode',
            '_mtmd_init_from_file', '_ov_create', '_ov_run', '_ov_cancel', '_ov_destroy',
            '_ov2_create_borrowed', '_ov2_validate', '_ov2_cancel', '_ov2_destroy', '_ov2_free',
            '_ov3_create_borrowed', '_ov3_generate'}

def inspect(root):
    info = plistlib.loads((root / 'Info.plist').read_bytes())
    libs = info.get('AvailableLibraries', [])
    expected = {('ios', None): {'arm64'}, ('ios', 'simulator'): {'arm64', 'x86_64'}}
    if len(libs) != 2:
        raise ValueError('Expected only device and simulator libraries')
    seen = set()
    binaries = []
    for item in libs:
        key = item.get('SupportedPlatform'), item.get('SupportedPlatformVariant')
        if key not in expected or key in seen or set(item.get('SupportedArchitectures', [])) != expected[key]:
            raise ValueError('Unexpected platform or architecture')
        seen.add(key)
        identifier = item['LibraryIdentifier']
        if '/' in identifier or identifier in ('', '.', '..') or item['LibraryPath'] != 'llama.framework':
            raise ValueError('Invalid library path')
        framework = root / identifier / 'llama.framework'
        for header in ('llama.h', 'mtmd.h', 'mtmd-helper.h', 'orivyn-tools.h', 'orivyn-vision.h'):
            if not (framework / 'Headers' / header).is_file():
                raise ValueError('Missing header: ' + header)
        module = (framework / 'Modules/module.modulemap').read_text()
        if not all('header "' + h + '"' in module for h in ('orivyn-tools.h', 'orivyn-vision.h')):
            raise ValueError('Missing combined C module exports')
        binary = framework / 'llama'
        if not binary.is_file():
            raise ValueError('Missing framework executable')
        binaries.append((binary, expected[key], key[1]))
    return binaries

def verify_load_commands(output, variant):
    blocks = re.split(r'(?m)^Load command \d+\s*$', output)
    versions = [block for block in blocks if re.search(r'(?m)^\s*cmd LC_BUILD_VERSION\s*$', block)]
    if len(versions) != 1:
        raise ValueError('Missing or ambiguous Mach-O build platform')
    block = versions[0]
    platform = re.search(r'(?m)^\s*platform (\S+)\s*$', block)
    allowed = {'7', 'IOSSIMULATOR'} if variant == 'simulator' else {'2', 'IOS'}
    if not platform or platform.group(1).upper() not in allowed:
        raise ValueError('Mach-O platform does not match iOS slice')
    minimum = re.search(r'(?m)^\s*minos (\d+)(?:\.(\d+))?(?:\.(\d+))?\s*$', block)
    if not minimum:
        raise ValueError('Missing Mach-O minimum OS')
    version = tuple(int(value or 0) for value in minimum.groups())
    if not (0, 0, 0) < version <= (17, 0, 0):
        raise ValueError('Runtime exceeds the reviewed iOS 17 framework deployment target')

def main():
    root = pathlib.Path(sys.argv[1])
    binaries = inspect(root)
    if sys.platform != 'darwin':
        raise SystemExit('Apple symbol/platform checks require macOS; runtime not admitted.')
    for binary, architectures, variant in binaries:
        for architecture in sorted(architectures):
            commands = subprocess.check_output(['xcrun', 'otool', '-arch', architecture, '-l', str(binary)], text=True)
            verify_load_commands(commands, variant)
            result = subprocess.check_output(['xcrun', 'nm', '-arch', architecture, '-gU', str(binary)], text=True)
            names = [line.split()[-1] for line in result.splitlines() if line.split()]
            if any(names.count(name) != 1 for name in REQUIRED):
                raise ValueError('Missing or duplicate combined runtime symbol')
        dependencies = subprocess.check_output(['xcrun', 'otool', '-L', str(binary)], text=True)
        if any(s in dependencies for s in ('libllama.', 'libggml', 'libmtmd')):
            raise ValueError('Second dynamic model runtime dependency')
    print('Combined runtime platform/header/symbol checks passed; runtime acceptance remains separate.')

if __name__ == '__main__':
    main()
