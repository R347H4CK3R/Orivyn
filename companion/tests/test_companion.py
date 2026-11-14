"""Real local filesystem/HTTP tests. No personal data, accounts or external network."""
import contextlib
import http.client
import importlib
import io
import json
import os
from pathlib import Path
import socket
import signal
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest import mock

try:
    c = importlib.import_module('companion.orivyn_companion')
except ModuleNotFoundError:
    c = None

TOKEN = 'test-only-not-a-real-secret-0123456789abcdef'


class WorkspaceTests(unittest.TestCase):
    def setUp(self):
        if c is None:
            self.fail('Missing feature: isolated companion workspace has not been implemented')
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'workspace'
        self.root.mkdir(mode=0o700)
        self.workspace = c.Workspace(self.root)
        self.addCleanup(self.workspace.close)

    def test_real_write_read_list_and_status_without_host_path(self):
        self.workspace.write('notes.txt', 'hello 🌎', False)
        self.assertEqual(self.workspace.read('notes.txt'), 'hello 🌎')
        self.assertEqual(self.workspace.list_files(), [{'name': 'notes.txt', 'bytes': 10}])
        status = self.workspace.status()
        self.assertEqual(status['files'], 1)
        self.assertEqual(status['bytes'], 10)
        self.assertNotIn(str(self.root), json.dumps(status))

    def test_overwrite_is_explicit_and_false_never_clobbers(self):
        self.workspace.write('note.txt', 'original', False)
        with self.assertRaises(c.CompanionError):
            self.workspace.write('note.txt', 'not approved', False)
        self.assertEqual(self.workspace.read('note.txt'), 'original')
        self.workspace.write('note.txt', 'approved', True)
        self.assertEqual(self.workspace.read('note.txt'), 'approved')

    def test_traversal_encoded_hidden_and_non_ascii_names_are_rejected(self):
        outside = Path(self.temp.name) / 'outside.txt'
        outside.write_text('private')
        for name in ['../outside.txt', '/etc/passwd', '.', '..', '.hidden', 'a/b', 'a\\b', '%2e%2e', 'a\x00b', 'a\nb', 'é.txt', 'a' * 129]:
            with self.subTest(name=repr(name)), self.assertRaises(c.CompanionError):
                self.workspace.write(name, 'bad', True)
        self.assertEqual(outside.read_text(), 'private')
        self.assertEqual(list(self.root.iterdir()), [])

    def test_symlink_file_read_write_and_list_never_access_target(self):
        outside = Path(self.temp.name) / 'secret.txt'
        outside.write_text('private')
        (self.root / 'alias.txt').symlink_to(outside)
        for action in [lambda: self.workspace.read('alias.txt'), lambda: self.workspace.write('alias.txt', 'bad', True), self.workspace.list_files]:
            with self.assertRaises(c.CompanionError):
                action()
        self.assertEqual(outside.read_text(), 'private')

    def test_hardlinks_and_subdirectories_are_not_workspace_files(self):
        outside = Path(self.temp.name) / 'outside.txt'
        outside.write_text('private')
        os.link(outside, self.root / 'alias.txt')
        with self.assertRaises(c.CompanionError):
            self.workspace.read('alias.txt')
        (self.root / 'alias.txt').unlink()
        (self.root / 'nested').mkdir()
        with self.assertRaises(c.CompanionError):
            self.workspace.list_files()

    def test_root_symlink_or_group_writable_root_is_refused(self):
        alias = Path(self.temp.name) / 'alias'
        alias.symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(c.CompanionError):
            c.Workspace(alias)
        os.chmod(self.root, 0o770)
        with self.assertRaises(c.CompanionError):
            c.Workspace(self.root)

    def test_unicode_write_byte_limit_and_file_read_limit(self):
        self.workspace.write('edge.txt', '😀' * 2048, False)
        with self.assertRaises(c.CompanionError):
            self.workspace.write('large.txt', '😀' * 2049, False)
        (self.root / 'large.txt').write_bytes(b'x' * 65537)
        with self.assertRaises(c.CompanionError):
            self.workspace.read('large.txt')

    def test_binary_and_nul_are_not_silently_decoded(self):
        (self.root / 'binary.txt').write_bytes(b'\xff')
        with self.assertRaises(c.CompanionError):
            self.workspace.read('binary.txt')
        with self.assertRaises(c.CompanionError):
            self.workspace.write('nul.txt', 'a\0b', False)

    def test_file_count_limit_preserves_existing_workspace(self):
        for i in range(128):
            (self.root / f'f{i}.txt').write_text('x')
        with self.assertRaises(c.CompanionError):
            self.workspace.write('extra.txt', 'x', False)
        self.workspace.write('f0.txt', 'ok', True)
        self.assertEqual(len(list(self.root.iterdir())), 128)

    def test_cancellation_before_commit_preserves_original(self):
        self.workspace.write('note.txt', 'original', False)
        cancelled = threading.Event(); cancelled.set()
        with self.assertRaises(c.CompanionError):
            self.workspace.write('note.txt', 'new', True, cancelled)
        self.assertEqual(self.workspace.read('note.txt'), 'original')
        self.assertEqual([p.name for p in self.root.iterdir()], ['note.txt'])

    def test_interrupted_real_write_keeps_original_and_removes_temporary(self):
        self.workspace.write('note.txt', 'original', False)
        real_write = os.write
        def partial(fd, data):
            real_write(fd, data[:1])
            raise OSError('fixture interrupted, no real secret')
        with mock.patch.object(c.os, 'write', side_effect=partial), self.assertRaises(c.CompanionError):
            self.workspace.write('note.txt', 'replacement', True)
        self.assertEqual(self.workspace.read('note.txt'), 'original')
        self.assertEqual([p.name for p in self.root.iterdir()], ['note.txt'])

    def test_token_file_exclusive_private_and_outside_served_root(self):
        token_file = Path(self.temp.name) / 'token'
        c.create_token(token_file, self.root)
        self.assertEqual(token_file.stat().st_mode & 0o777, 0o600)
        first = c.load_token(token_file, self.root, {})
        self.assertGreaterEqual(len(first), 32)
        with self.assertRaises(c.CompanionError):
            c.create_token(token_file, self.root)
        self.assertEqual(c.load_token(token_file, self.root, {}), first)
        with self.assertRaises(c.CompanionError):
            c.create_token(self.root / 'token', self.root)
        hardlink = Path(self.temp.name) / 'hardlink'
        os.link(token_file, hardlink)
        with self.assertRaises(c.CompanionError):
            c.load_token(token_file, self.root, {})
        hardlink.unlink()
        os.chmod(token_file, 0o644)
        with self.assertRaises(c.CompanionError):
            c.load_token(token_file, self.root, {})

    def test_token_symlink_and_invalid_env_refused_without_echo(self):
        token_file = Path(self.temp.name) / 'token'
        token_file.write_text(TOKEN); token_file.chmod(0o600)
        alias = Path(self.temp.name) / 'alias'; alias.symlink_to(token_file)
        with self.assertRaises(c.CompanionError):
            c.load_token(alias, self.root, {})
        with self.assertRaises(c.CompanionError) as caught:
            c.load_token(None, self.root, {'ORIVYN_COMPANION_TOKEN': 'secret\r\nheader'})
        self.assertNotIn('secret', str(caught.exception))

    def test_real_cli_generates_secret_without_logging_it_or_overwriting(self):
        token_file = Path(self.temp.name) / 'cli.token'
        command = [sys.executable, str(Path(c.__file__)), '--workspace', str(self.root), '--token-file', str(token_file), '--init-token']
        result = subprocess.run(command, capture_output=True, text=True, timeout=3)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        secret = token_file.read_text()
        self.assertNotIn(secret, result.stdout + result.stderr)
        self.assertNotIn(str(token_file), result.stdout + result.stderr)
        again = subprocess.run(command, capture_output=True, text=True, timeout=3)
        self.assertNotEqual(again.returncode, 0)
        self.assertEqual(token_file.read_text(), secret)

    def test_real_cli_starts_local_authenticated_server_and_stops_cleanly(self):
        token_file = Path(self.temp.name) / 'cli.token'
        c.create_token(token_file, self.root)
        with socket.socket() as reservation:
            reservation.bind(('127.0.0.1', 0)); port = reservation.getsockname()[1]
        command = [sys.executable, str(Path(c.__file__)), '--workspace', str(self.root), '--token-file', str(token_file), '--port', str(port)]
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            deadline = time.monotonic() + 2
            status = None
            while time.monotonic() < deadline:
                conn = http.client.HTTPConnection('127.0.0.1', port, timeout=1)
                try:
                    conn.request('POST', '/mcp', b'{}', {'Content-Type':'application/json'})
                    response = conn.getresponse(); response.read(); status = response.status; break
                except ConnectionRefusedError: time.sleep(0.02)
                finally: conn.close()
            self.assertEqual(status, 401)
        finally:
            process.send_signal(signal.SIGINT)
            try: out, err = process.communicate(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill(); out, err = process.communicate(); self.fail('CLI did not stop cleanly')
        self.assertEqual(process.returncode, 0, out + err)
        self.assertEqual(err, '')
        self.assertNotIn(token_file.read_text(), out)

    def test_strict_json_duplicate_deep_and_nonfinite_rejected(self):
        for raw in [b'{"a":1,"a":2}', b'{"n":NaN}', b'[' * 17 + b'0' + b']' * 17, b'{"x":1e999}', b'"\\ud800"']:
            with self.subTest(raw=raw), self.assertRaises(c.CompanionError):
                c.decode_json(raw)

    def test_schema_validation_rejects_unknown_missing_wrong_types_and_large_args(self):
        for args in [{}, {'name':'x','text':'x'}, {'name':'x','text':'x','overwrite':1}, {'name':'x','text':'x','overwrite':False,'extra':'x'}, {'name':'x','text':'x'*17000,'overwrite':False}]:
            with self.assertRaises(c.CompanionError):
                c.validate_arguments('workspace.write', args)
        self.assertEqual(c.validate_arguments('workspace.read', {'name': 'note.txt'}), {'name': 'note.txt'})


class HTTPTests(unittest.TestCase):
    def setUp(self):
        if c is None:
            self.fail('Missing feature: authenticated companion MCP HTTP server has not been implemented')
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'workspace'; self.root.mkdir(mode=0o700)
        self.workspace = c.Workspace(self.root); self.addCleanup(self.workspace.close)
        self.server = c.make_server(self.workspace, TOKEN, port=0, request_timeout=0.6)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True); self.thread.start()
        self.addCleanup(self.stop)
        self.port = self.server.server_address[1]
        self.session = None
        self.sequence = 0

    def stop(self):
        self.server.shutdown(); self.server.server_close(); self.thread.join(timeout=2)

    def send(self, body, *, method='POST', session=True, token=TOKEN, headers=None, path='/mcp'):
        conn = http.client.HTTPConnection('127.0.0.1', self.port, timeout=3)
        data = body if isinstance(body, bytes) else json.dumps(body, separators=(',',':')).encode()
        h = {'Authorization':'Bearer '+token, 'Content-Type':'application/json', 'MCP-Protocol-Version':'2025-06-18'}
        if session and self.session: h['Mcp-Session-Id'] = self.session
        if headers: h.update(headers)
        try:
            conn.request(method, path, data, h)
            response = conn.getresponse(); payload = response.read()
            return response.status, dict(response.getheaders()), json.loads(payload) if payload else None
        finally:
            conn.close()

    def rpc(self, method, params=None, request_id=None, **kwargs):
        self.sequence += 1
        return self.send({'jsonrpc':'2.0','id':request_id or str(self.sequence),'method':method,'params':params or {}}, **kwargs)

    def initialize(self):
        status, headers, body = self.rpc('initialize', {'protocolVersion':'2025-06-18','capabilities':{},'clientInfo':{'name':'Test','version':'1'}}, session=False)
        self.assertEqual(status, 200)
        self.assertEqual(body['result']['protocolVersion'], '2025-06-18')
        self.session = headers['Mcp-Session-Id']
        status, _, body = self.send({'jsonrpc':'2.0','method':'notifications/initialized'})
        self.assertEqual(status, 202); self.assertIsNone(body)

    def test_authenticated_real_handshake_catalog_write_read_roundtrip(self):
        self.initialize()
        status, _, reply = self.rpc('tools/list')
        self.assertEqual(status, 200)
        self.assertEqual({t['name'] for t in reply['result']['tools']}, {'companion.status','workspace.list','workspace.read','workspace.write'})
        for tool in reply['result']['tools']:
            self.assertEqual(tool['inputSchema']['type'], 'object')
            self.assertFalse(tool['inputSchema']['additionalProperties'])
        _, _, result = self.rpc('tools/call', {'name':'workspace.write','arguments':{'name':'note.txt','text':'hello','overwrite':False}})
        self.assertFalse(result['result']['isError'])
        self.assertEqual((self.root / 'note.txt').read_text(), 'hello')
        _, _, result = self.rpc('tools/call', {'name':'workspace.read','arguments':{'name':'note.txt'}})
        self.assertEqual(result['result']['content'], [{'type':'text','text':'hello'}])

    def test_authentication_failure_never_handshakes_or_echoes_secret(self):
        status, _, reply = self.rpc('initialize', token='private-wrong-token')
        self.assertEqual(status, 401)
        self.assertNotIn('private-wrong-token', json.dumps(reply))
        self.assertEqual(list(self.root.iterdir()), [])

    def test_origin_host_path_and_content_type_rejected(self):
        for extra in [{'Origin':'https://evil.invalid'}, {'Host':'evil.invalid'}, {'Content-Type':'text/plain'}]:
            status, _, _ = self.rpc('initialize', headers=extra)
            self.assertIn(status, (400,403,415))
        status, _, _ = self.rpc('initialize', path='/mcp?token=anything')
        self.assertEqual(status, 404)

    def test_explicit_public_host_allowlist_accepts_proxy_not_arbitrary_host(self):
        other = c.make_server(self.workspace, TOKEN, port=0, public_host='owner.example.ts.net')
        thread = threading.Thread(target=other.serve_forever, daemon=True); thread.start()
        old_port = self.port; self.port = other.server_address[1]
        try:
            status, _, _ = self.rpc('initialize', {'protocolVersion':'2025-06-18','capabilities':{},'clientInfo':{'name':'Test','version':'1'}}, headers={'Host':'owner.example.ts.net'})
            self.assertEqual(status, 200)
            status, _, _ = self.rpc('initialize', headers={'Host':'attacker.example.ts.net'})
            self.assertEqual(status, 403)
        finally:
            self.port = old_port; other.shutdown(); other.server_close(); thread.join(timeout=2)

    def test_wrong_version_or_session_cannot_discover_or_call(self):
        status, _, _ = self.rpc('initialize', {'protocolVersion':'2024-11-05'})
        self.assertEqual(status, 400)
        self.initialize()
        status, _, _ = self.rpc('tools/list', headers={'MCP-Protocol-Version':'wrong'})
        self.assertEqual(status, 400)
        status, _, _ = self.rpc('tools/list', headers={'Mcp-Session-Id':'unknown'})
        self.assertEqual(status, 404)

    def test_initialized_notification_required_before_tools(self):
        _, headers, _ = self.rpc('initialize', {'protocolVersion':'2025-06-18','capabilities':{},'clientInfo':{'name':'Test','version':'1'}}, session=False)
        self.session = headers['Mcp-Session-Id']
        status, _, _ = self.rpc('tools/list')
        self.assertEqual(status, 409)

    def test_schema_and_traversal_errors_do_not_write(self):
        self.initialize()
        for arguments in [{'name':'../escape','text':'no','overwrite':True}, {'name':'safe','text':'no','overwrite':'true'}, {'name':'safe','text':'no','overwrite':False,'shell':'rm'}]:
            _, _, reply = self.rpc('tools/call', {'name':'workspace.write','arguments':arguments})
            self.assertTrue('error' in reply or reply.get('result',{}).get('isError'))
        self.assertEqual(list(self.root.iterdir()), [])

    def test_reused_request_id_never_repeats_or_changes_write(self):
        self.initialize()
        params = {'name':'workspace.write','arguments':{'name':'once','text':'first','overwrite':True}}
        self.rpc('tools/call', params, request_id='one-shot')
        params['arguments']['text'] = 'duplicate'
        status, _, _ = self.rpc('tools/call', params, request_id='one-shot')
        self.assertEqual(status, 409)
        self.assertEqual((self.root / 'once').read_text(), 'first')

    def test_session_delete_is_explicit_and_does_not_delete_files(self):
        self.initialize(); (self.root / 'keep.txt').write_text('keep')
        status, _, _ = self.send(b'', method='DELETE')
        self.assertIn(status, (200,204))
        status, _, _ = self.rpc('tools/list')
        self.assertEqual(status, 404)
        self.assertEqual((self.root / 'keep.txt').read_text(), 'keep')

    def test_oversized_malformed_duplicate_and_batch_json_refused(self):
        for body in [b'[' + b'{}' + b']', b'{"jsonrpc":"2.0","jsonrpc":"2.0"}', b'{bad', b'x'*32769]:
            status, _, _ = self.send(body)
            self.assertIn(status, (400,413))

    def test_no_payload_paths_or_tokens_written_to_logs(self):
        with contextlib.redirect_stderr(io.StringIO()) as err, contextlib.redirect_stdout(io.StringIO()) as out:
            self.rpc('initialize', {'private':'untrusted marker'}, token='private-marker')
            self.send(b'{bad')
        self.assertEqual(err.getvalue() + out.getvalue(), '')

    def test_eight_session_limit_does_not_allocate_unbounded_sessions(self):
        for _ in range(8): self.initialize()
        status, _, _ = self.rpc('initialize', {'protocolVersion':'2025-06-18','capabilities':{},'clientInfo':{'name':'Test','version':'1'}}, session=False)
        self.assertEqual(status, 503)

    def test_slow_header_connection_is_closed_by_absolute_deadline(self):
        sock = socket.create_connection(('127.0.0.1', self.port), timeout=2)
        self.addCleanup(sock.close)
        sock.sendall(b'POST /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\n')
        start = time.monotonic()
        self.assertEqual(sock.recv(1024), b'')
        self.assertLess(time.monotonic() - start, 1.8)

    def test_worker_capacity_refuses_fifth_slow_request(self):
        sockets = []
        try:
            for _ in range(4):
                sock = socket.create_connection(('127.0.0.1', self.port), timeout=2)
                sock.sendall(b'POST /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\n')
                sockets.append(sock)
            status, _, _ = self.send(b'{}')
            self.assertEqual(status, 503)
        finally:
            for sock in sockets: sock.close()

    def test_expired_session_requires_new_handshake_without_replay(self):
        self.initialize()
        future = time.monotonic() + 901
        with mock.patch.object(c.time, 'monotonic', return_value=future):
            status, _, _ = self.rpc('tools/list')
        self.assertEqual(status, 404)
        self.assertEqual(list(self.root.iterdir()), [])

    def test_request_ledger_fills_without_evicting_and_repeating_old_write(self):
        self.initialize()
        self.rpc('tools/call', {'name':'workspace.write','arguments':{'name':'once','text':'first','overwrite':True}}, request_id='first-write')
        for _ in range(126):
            status, _, _ = self.rpc('tools/list')
            self.assertEqual(status, 200)
        status, _, _ = self.rpc('tools/call', {'name':'workspace.write','arguments':{'name':'once','text':'repeat','overwrite':True}}, request_id='first-write')
        self.assertEqual(status, 409)
        status, _, _ = self.rpc('tools/list')
        self.assertEqual(status, 409)
        self.assertEqual((self.root / 'once').read_text(), 'first')

    def test_non_ascii_authorization_returns_redacted_failure_not_exception(self):
        try:
            status, _, reply = self.rpc('initialize', headers={'Authorization':'Bearer é-private'})
        except http.client.RemoteDisconnected:
            self.fail('Non-ASCII authorization crashes request handling instead of a redacted 401')
        self.assertEqual(status, 401)
        self.assertNotIn('private', json.dumps(reply))

    def test_duplicate_authorization_and_chunked_requests_rejected(self):
        for extra in [b'Authorization: Bearer duplicate\r\n', b'Transfer-Encoding: chunked\r\n']:
            sock = socket.create_connection(('127.0.0.1', self.port), timeout=2)
            try:
                sock.sendall(b'POST /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer '+TOKEN.encode()+b'\r\nContent-Type: application/json\r\nContent-Length: 2\r\n'+extra+b'\r\n{}')
                response = sock.recv(4096)
                self.assertIn(b' 400 ', response)
            finally: sock.close()

    def test_disconnected_writer_is_never_replayed_by_duplicate_id(self):
        self.initialize()
        body = json.dumps({'jsonrpc':'2.0','id':'lost-response','method':'tools/call','params':{'name':'workspace.write','arguments':{'name':'once','text':'committed','overwrite':True}}}).encode()
        sock = socket.create_connection(('127.0.0.1', self.port), timeout=2)
        header = ('POST /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer '+TOKEN+'\r\nMCP-Protocol-Version: 2025-06-18\r\nMcp-Session-Id: '+self.session+'\r\nContent-Type: application/json\r\nContent-Length: '+str(len(body))+'\r\n\r\n').encode()
        sock.sendall(header+body); sock.close()
        deadline = time.monotonic()+1
        while not (self.root / 'once').exists() and time.monotonic()<deadline:
            time.sleep(0.01)
        self.assertEqual((self.root / 'once').read_text(), 'committed')
        status, _, _ = self.rpc('tools/call', {'name':'workspace.write','arguments':{'name':'once','text':'replayed','overwrite':True}}, request_id='lost-response')
        self.assertEqual(status, 409)
        self.assertEqual((self.root / 'once').read_text(), 'committed')

    def test_cancel_notification_before_atomic_commit_prevents_write(self):
        self.initialize()
        entered, release = threading.Event(), threading.Event()
        original = os.fsync
        def blocked(fd):
            entered.set()
            if not release.wait(2): raise OSError('fixture timeout')
            return original(fd)
        result = []
        params = {'name':'workspace.write','arguments':{'name':'cancel.txt','text':'never','overwrite':False}}
        with mock.patch.object(c.os, 'fsync', side_effect=blocked):
            thread = threading.Thread(target=lambda: result.append(self.rpc('tools/call', params, request_id='cancel-me')))
            thread.start()
            try:
                self.assertTrue(entered.wait(1))
                status, _, _ = self.send({'jsonrpc':'2.0','method':'notifications/cancelled','params':{'requestId':'cancel-me'}})
                self.assertEqual(status, 202)
            finally:
                release.set(); thread.join(timeout=3)
        self.assertFalse((self.root / 'cancel.txt').exists())
        self.assertEqual(list(self.root.iterdir()), [])
        self.assertTrue(result[0][2]['result']['isError'])


if __name__ == '__main__': unittest.main()
