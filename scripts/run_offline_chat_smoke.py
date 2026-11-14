#!/usr/bin/env python3
"""Compile exact production offline chat/persistence sources with installed Swift/llama/SQLite.
No downloads, substitutes, remote service, or Apple/iPhone verification. Driver is explicit.
"""
import argparse
import hashlib
import json
import os
import pathlib
import shutil
import signal
import subprocess
import time
from run_llama_engine_smoke import SOURCES as ENGINE_SOURCES

SOURCES = [n for n in ENGINE_SOURCES if n != 'scripts/swift-smoke/LlamaEngineSmoke.swift'] + [
    'JarvisEVO/Core/ConversationSearch.swift',
    'JarvisEVO/Persistence/SQLiteConversationStore.swift',
    'scripts/swift-smoke/OfflineChatSmoke.swift',
]


def digest(path):
    path = pathlib.Path(path)
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return {'path': str(path.resolve()), 'bytes': path.stat().st_size, 'sha256': h.hexdigest()}


def execute(command, env, log, timeout):
    """Reap the whole owned process group on timeout; never leave compiler/model workers."""
    started = time.monotonic()
    try:
        process = subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    except OSError as error:
        log.write(('Launch failed: ' + str(error) + '\n').encode()); log.flush()
        return {'exit': 127, 'error': str(error), 'elapsedSeconds': time.monotonic() - started}
    timed_out = False
    try:
        code = process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()
        code = 124
        log.write(('Stage timed out after ' + str(timeout) + ' seconds; owned process group reaped.\n').encode())
    log.flush()
    return {'exit': code, 'pid': process.pid, 'timeout': timed_out,
            'processReaped': process.poll() is not None, 'elapsedSeconds': time.monotonic() - started}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['swiftc', 'runtime', 'headers', 'model', 'output', 'sqlite-source']:
        parser.add_argument('--' + name, required=True, type=pathlib.Path)
    args = parser.parse_args()
    root = pathlib.Path(__file__).resolve().parents[1]
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    started = time.monotonic()
    report = {'sqliteCompileExit': None, 'compileExit': None, 'runtimeExit': None,
              'exactProductionSwiftEngineAndPersistence': True, 'linuxBackendSetupInDriver': True,
              'appleFrameworkVerified': False, 'iPhoneVerified': False, 'stages': {}}
    manifest, files = [], []
    code = 1
    try:
        def copy(source, destination, label):
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, destination)
            entry = digest(destination)
            entry.update({'source': label, 'copiedTo': str(destination.relative_to(out))})
            manifest.append(entry)

        for name in SOURCES:
            destination = out / 'sources' / pathlib.Path(name).name
            copy(root / name, destination, name)
            files.append(str(destination))
        resource = 'JarvisEVO/Resources/LocalAgentDecision.gbnf'
        copy(root / resource, out / 'LocalAgentDecision.gbnf', resource)
        llama_module = out / 'llama'
        for source in sorted(args.headers.rglob('*')):
            if source.is_file():
                relative = source.relative_to(args.headers)
                copy(source, llama_module / 'include' / relative, 'external-llama-headers/' + str(relative))
        if not (llama_module / 'include/llama.h').is_file():
            raise ValueError('Matching headers directory must contain llama.h')
        (llama_module / 'module.modulemap').write_text('module llama [system] { header "include/llama.h" link "llama" export * }\n')
        sqlite_module = out / 'SQLite3'
        copy(args.sqlite_source / 'sqlite3.c', sqlite_module / 'sqlite3.c', 'external-official-sqlite/sqlite3.c')
        copy(args.sqlite_source / 'sqlite3.h', sqlite_module / 'include/sqlite3.h', 'external-official-sqlite/sqlite3.h')
        (sqlite_module / 'module.modulemap').write_text('module SQLite3 [system] { header "include/sqlite3.h" export * }\n')
        (out / 'SOURCE-MANIFEST.json').write_text(json.dumps(manifest, indent=2) + '\n')
        runtime = args.runtime.resolve()
        seen, libraries = set(), []
        for library in sorted(runtime.glob('*.so*')):
            if library.is_file() and library.resolve() not in seen:
                seen.add(library.resolve()); libraries.append(digest(library))
        (out / 'RUNTIME-MODEL-MANIFEST.json').write_text(json.dumps({'model': digest(args.model), 'libraries': libraries}, indent=2) + '\n')
        for name in ['home', 'tmp', 'state']:
            (out / name).mkdir()
        env = dict(os.environ, HOME=str(out / 'home'), TMPDIR=str(out / 'tmp'),
                   LD_LIBRARY_PATH=str(runtime), CLANG_MODULE_CACHE_PATH=str(out / 'module-cache'))
        sqlite_command = ['cc', '-c', '-O2', '-fPIC', '-DSQLITE_THREADSAFE=1',
                          '-I', str(sqlite_module / 'include'), str(sqlite_module / 'sqlite3.c'), '-o', str(sqlite_module / 'sqlite3.o')]
        swift_command = [str(args.swiftc), '-swift-version', '6', '-parse-as-library',
                         '-module-cache-path', str(out / 'module-cache'), '-I', str(llama_module), '-I', str(sqlite_module),
                         '-L', str(runtime), '-lllama', '-lggml', '-Xlinker', '-rpath', '-Xlinker', str(runtime),
                         *files, str(sqlite_module / 'sqlite3.o'), '-ldl', '-lm', '-o', str(out / 'offline-chat-smoke')]
        run_command = [str(out / 'offline-chat-smoke'), str(args.model.resolve()), str(runtime), str(out / 'state')]
        commands = {'swiftVersion': [str(args.swiftc), '--version'], 'ccVersion': ['cc', '--version'],
                    'sqliteCompile': sqlite_command, 'swiftCompile': swift_command, 'run': run_command}
        (out / 'COMMANDS.json').write_text(json.dumps(commands, indent=2) + '\n')
        with (out / 'TOOLCHAIN.txt').open('wb') as log:
            for name in ['swiftVersion', 'ccVersion']:
                stage = execute(commands[name], env, log, 30)
                report['stages'][name] = stage
                if stage['exit']:
                    code = stage['exit']; return code
        with (out / 'smoke.log').open('wb') as log:
            for name, command, timeout, exit_key in [
                ('sqliteCompile', sqlite_command, 180, 'sqliteCompileExit'),
                ('swiftCompile', swift_command, 180, 'compileExit'),
                ('run', run_command, 240, 'runtimeExit'),
            ]:
                log.write(('\n=== ' + name + ' ===\n').encode()); log.flush()
                stage = execute(command, env, log, timeout)
                report['stages'][name] = stage; report[exit_key] = stage['exit']; code = stage['exit']
                if code:
                    break
        print((out / 'smoke.log').read_text(errors='replace'))
        return code
    except (OSError, ValueError) as error:
        report['setupError'] = str(error)
        print('Offline chat smoke setup failed:', error)
        return 1
    finally:
        report['elapsedSeconds'] = time.monotonic() - started
        (out / 'RESULT.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    raise SystemExit(main())
