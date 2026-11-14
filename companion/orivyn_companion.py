#!/usr/bin/env python3
"""Free, bounded workspace MCP. Localhost only; no shell, browser or host API."""
from __future__ import annotations

import argparse
from dataclasses import dataclass, field
import hmac
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import re
import secrets
import socket
from socketserver import ThreadingMixIn
import stat
import threading
import time

PROTOCOL = '2025-06-18'
VERSION = '0.1.0'
MAX_FILES = 128
MAX_TOTAL = 8 * 1024 * 1024
MAX_FILE = 65536
MAX_WRITE = 8192
MAX_BODY = 32768
MAX_ARGS = 16384
MAX_RESPONSE = 1048576
NAME = re.compile(r'[A-Za-z0-9][A-Za-z0-9._-]{0,127}\Z', re.ASCII)
TOKEN = re.compile(r'[A-Za-z0-9_-]{32,128}\Z', re.ASCII)


class CompanionError(Exception):
    """Fixed public messages only. Never interpolate filesystem or request data."""


def safe_error() -> CompanionError:
    return CompanionError('Workspace operation refused or interrupted. Inspect its state before retrying.')


def encode_json(value) -> bytes:
    return json.dumps(value, ensure_ascii=False, separators=(',', ':'), allow_nan=False).encode('utf-8')


def _bounded(value, depth=0):
    if depth > 16:
        raise CompanionError('JSON nesting exceeds the limit.')
    if isinstance(value, dict):
        if len(value) > 64:
            raise CompanionError('Too many object properties.')
        for key, item in value.items():
            if len(key.encode('utf-8')) > MAX_ARGS:
                raise CompanionError('JSON value exceeds the limit.')
            _bounded(item, depth + 1)
    elif isinstance(value, list):
        if len(value) > 128:
            raise CompanionError('Too many array items.')
        for item in value:
            _bounded(item, depth + 1)
    elif isinstance(value, str):
        if len(value.encode('utf-8')) > MAX_BODY:
            raise CompanionError('JSON value exceeds the limit.')
    elif type(value) in (int, float):
        if not (-9007199254740991 <= value <= 9007199254740991):
            raise CompanionError('Unsafe JSON number.')
    elif value is not None and not isinstance(value, bool):
        raise CompanionError('Unsupported JSON value.')


def decode_json(raw: bytes):
    if len(raw) > MAX_BODY:
        raise CompanionError('Request exceeds the limit.')
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise CompanionError('Duplicate JSON key.')
            result[key] = value
        return result
    def reject(_):
        raise CompanionError('Nonfinite JSON number.')
    try:
        # Byte cap bounds parser allocation; depth scanner precedes recursive decode.
        depth, quoted, escaped = 0, False, False
        for byte in raw:
            if quoted:
                if escaped: escaped = False
                elif byte == 92: escaped = True
                elif byte == 34: quoted = False
            elif byte == 34: quoted = True
            elif byte in (91, 123):
                depth += 1
                if depth > 16: raise CompanionError('JSON nesting exceeds the limit.')
            elif byte in (93, 125): depth -= 1
        value = json.loads(raw.decode('utf-8'), object_pairs_hook=pairs, parse_constant=reject)
        _bounded(value)
        return value
    except (ValueError, UnicodeError, RecursionError) as exc:
        raise CompanionError('Invalid JSON.') from None


def schema(properties=None, required=None):
    return {'type': 'object', 'properties': properties or {}, 'required': required or [], 'additionalProperties': False}


TOOLS = [
    {'name': 'companion.status', 'description': 'Report limits and counts of this dedicated workspace only.', 'inputSchema': schema()},
    {'name': 'workspace.list', 'description': 'List bounded flat workspace filenames and sizes, not host files.', 'inputSchema': schema()},
    {'name': 'workspace.read', 'description': 'Read one UTF-8 file in the dedicated workspace, up to 64 KiB.', 'inputSchema': schema({'name': {'type': 'string', 'minLength': 1, 'maxLength': 128}}, ['name'])},
    {'name': 'workspace.write', 'description': 'Atomically write up to 8 KiB of UTF-8 text. Overwriting an existing file requires overwrite=true. This changes a real file.', 'inputSchema': schema({'name': {'type': 'string', 'minLength': 1, 'maxLength': 128}, 'text': {'type': 'string', 'maxLength': 8192}, 'overwrite': {'type': 'boolean'}}, ['name', 'text', 'overwrite'])},
]


def validate_arguments(tool: str, arguments: dict) -> dict:
    definition = next((x for x in TOOLS if x['name'] == tool), None)
    try:
        if definition is None or type(arguments) is not dict or len(encode_json(arguments)) > MAX_ARGS:
            raise CompanionError('Unsupported tool or arguments.')
        _bounded(arguments)
        spec = definition['inputSchema']
        if set(arguments) != set(spec['required']):
            raise CompanionError('Required arguments are missing or unknown.')
        for key, prop in spec['properties'].items():
            value = arguments[key]
            if prop['type'] == 'boolean':
                if type(value) is not bool: raise CompanionError('Invalid argument type.')
            elif type(value) is not str or not prop.get('minLength', 0) <= len(value) <= prop['maxLength']:
                raise CompanionError('Invalid argument length or type.')
        return arguments
    except (ValueError, UnicodeError, TypeError):
        raise CompanionError('Invalid arguments.') from None


def valid_name(name):
    if type(name) is not str or not NAME.fullmatch(name):
        raise safe_error()


class Workspace:
    """Pinned directory descriptor; application confinement, not an OS sandbox."""
    def __init__(self, root: Path):
        self.fd = -1
        self.lock = threading.RLock()
        try:
            if os.name != 'posix' or not hasattr(os, 'O_NOFOLLOW'):
                raise safe_error()
            root = Path(root).absolute()
            if root != root.resolve(strict=True): raise safe_error()
            self.fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
            info = os.fstat(self.fd)
            if info.st_uid != os.getuid() or info.st_mode & 0o022: raise safe_error()
            self.device = info.st_dev
            self._scan()
        except (OSError, ValueError, CompanionError):
            self.close()
            raise safe_error() from None

    def close(self):
        with self.lock:
            if self.fd >= 0:
                os.close(self.fd); self.fd = -1

    def _info(self, name):
        info = os.stat(name, dir_fd=self.fd, follow_symlinks=False)
        if (not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_uid != os.getuid()
                or info.st_dev != self.device or info.st_size > MAX_FILE):
            raise safe_error()
        return info

    def _scan(self):
        rows, total = [], 0
        # scandir iteration is bounded even if another local process adds many files.
        with os.scandir(self.fd) as entries:
            for entry in entries:
                if len(rows) >= MAX_FILES: raise safe_error()
                valid_name(entry.name)
                info = self._info(entry.name)
                total += info.st_size
                if total > MAX_TOTAL: raise safe_error()
                rows.append({'name': entry.name, 'bytes': info.st_size})
        return sorted(rows, key=lambda row: row['name'])

    def list_files(self):
        with self.lock:
            try: return self._scan()
            except OSError: raise safe_error() from None

    def status(self):
        rows = self.list_files()
        return {'serverVersion': VERSION, 'protocolVersion': PROTOCOL, 'files': len(rows),
                'bytes': sum(row['bytes'] for row in rows), 'maxFiles': MAX_FILES,
                'maxTotalBytes': MAX_TOTAL, 'maxReadBytes': MAX_FILE, 'maxWriteBytes': MAX_WRITE,
                'capabilities': ['flat-text-workspace'], 'desktopControl': False}

    def read(self, name):
        valid_name(name)
        with self.lock:
            fd = -1
            try:
                self._scan()
                fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=self.fd)
                info = os.fstat(fd)
                if (not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_uid != os.getuid()
                        or info.st_dev != self.device or info.st_size > MAX_FILE): raise safe_error()
                result = bytearray()
                while True:
                    data = os.read(fd, min(8192, MAX_FILE + 1 - len(result)))
                    if not data: break
                    result.extend(data)
                    if len(result) > MAX_FILE: raise safe_error()
                text = result.decode('utf-8')
                if '\0' in text: raise safe_error()
                return text
            except (OSError, UnicodeError): raise safe_error() from None
            finally:
                if fd >= 0: os.close(fd)

    def write(self, name, text, overwrite, cancel_event=None):
        valid_name(name)
        try: data = text.encode('utf-8')
        except (AttributeError, UnicodeError): raise safe_error() from None
        if type(overwrite) is not bool or len(data) > MAX_WRITE or '\0' in text: raise safe_error()
        with self.lock:
            temporary, fd = None, -1
            try:
                rows = self._scan()
                previous = next((x for x in rows if x['name'] == name), None)
                if previous and not overwrite: raise safe_error()
                if previous is None and len(rows) >= MAX_FILES: raise safe_error()
                if sum(x['bytes'] for x in rows) - (previous['bytes'] if previous else 0) + len(data) > MAX_TOTAL: raise safe_error()
                if cancel_event is not None and cancel_event.is_set(): raise safe_error()
                temporary = '.orivyn-' + secrets.token_hex(16)
                fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=self.fd)
                remaining = memoryview(data)
                while remaining:
                    written = os.write(fd, remaining)
                    if written <= 0: raise safe_error()
                    remaining = remaining[written:]
                os.fsync(fd); os.close(fd); fd = -1
                if cancel_event is not None and cancel_event.is_set(): raise safe_error()
                # Revalidate the existing target immediately before replacement.
                try:
                    self._info(name)
                    if not overwrite: raise safe_error()
                except FileNotFoundError: pass
                if overwrite:
                    os.replace(temporary, name, src_dir_fd=self.fd, dst_dir_fd=self.fd)
                    temporary = None
                else:
                    os.link(temporary, name, src_dir_fd=self.fd, dst_dir_fd=self.fd, follow_symlinks=False)
                    os.unlink(temporary, dir_fd=self.fd); temporary = None
                os.fsync(self.fd)
                return {'name': name, 'bytes': len(data), 'written': True}
            except OSError: raise safe_error() from None
            finally:
                if fd >= 0: os.close(fd)
                if temporary is not None:
                    try: os.unlink(temporary, dir_fd=self.fd)
                    except OSError: pass


def _token_path(path, workspace):
    if path is None: raise CompanionError('A private token file or token environment variable is required.')
    try:
        path = Path(path).absolute()
        parent = path.parent.resolve(strict=True)
        root = Path(workspace).resolve(strict=True)
        if parent != path.parent or path == root or root in path.parents:
            raise CompanionError('Token storage must be outside the workspace without symlinks.')
        return path
    except OSError: raise CompanionError('Token storage is unavailable.') from None


def create_token(path, workspace):
    path = _token_path(path, workspace)
    fd = -1
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        value = secrets.token_urlsafe(32).encode('ascii')
        if os.write(fd, value) != len(value): raise CompanionError('Token creation was interrupted.')
        os.fsync(fd)
    except OSError: raise CompanionError('Token creation refused; existing files were not replaced.') from None
    finally:
        if fd >= 0: os.close(fd)


def load_token(path, workspace, environment=None):
    environment = os.environ if environment is None else environment
    value = environment.get('ORIVYN_COMPANION_TOKEN')
    if value is None:
        path = _token_path(path, workspace)
        fd = -1
        try:
            fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
            info = os.fstat(fd)
            if (not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_uid != os.getuid()
                    or info.st_mode & 0o777 != 0o600 or info.st_size > 128):
                raise CompanionError('Token file must be private, regular and owned by this user.')
            value = os.read(fd, 129).decode('ascii')
        except (OSError, UnicodeError): raise CompanionError('Token file could not be read safely.') from None
        finally:
            if fd >= 0: os.close(fd)
    if type(value) is not str or not TOKEN.fullmatch(value): raise CompanionError('Invalid token format.')
    return value


@dataclass
class Session:
    touched: float
    ready: bool = False
    used: set = field(default_factory=set)
    active_id: str | None = None
    cancelled: threading.Event | None = None


class Protocol:
    def __init__(self, workspace, token):
        if not TOKEN.fullmatch(token): raise CompanionError('Invalid token format.')
        self.workspace, self.token = workspace, token
        self.sessions = {}
        self.lock = threading.RLock()

    def dispatch(self, method, headers, raw, abort):
        if not self.authenticated(headers.get('authorization', '')):
            return self.error(401, None, -32001, 'Authentication required.')
        version = headers.get('mcp-protocol-version')
        if version != PROTOCOL:
            return self.error(400, None, -32600, 'Unsupported protocol version.')
        if method == 'DELETE':
            with self.lock:
                session = self.sessions.pop(headers.get('mcp-session-id'), None)
                if session is None: return self.error(404, None, -32000, 'Session unavailable.')
                if session.cancelled: session.cancelled.set()
            return 204, {}, None
        try:
            message = decode_json(raw)
        except CompanionError:
            return self.error(400, None, -32700, 'Invalid or oversized JSON.')
        if type(message) is not dict or message.get('jsonrpc') != '2.0' or set(message) - {'jsonrpc','id','method','params'}:
            return self.error(400, None, -32600, 'Invalid request.')
        request_id = message.get('id')
        if request_id is not None and (type(request_id) is not str or not 1 <= len(request_id) <= 128):
            return self.error(400, None, -32600, 'A bounded string request ID is required.')
        method = message.get('method'); params = message.get('params', {})
        if type(method) is not str or type(params) is not dict:
            return self.error(400, request_id, -32600, 'Invalid request.')
        with self.lock:
            now = time.monotonic()
            for key, session in list(self.sessions.items()):
                if now - session.touched > 900:
                    if session.cancelled: session.cancelled.set()
                    del self.sessions[key]
            if method == 'initialize':
                if (request_id is None or headers.get('mcp-session-id') is not None or params.get('protocolVersion') != PROTOCOL
                        or type(params.get('capabilities')) is not dict or type(params.get('clientInfo')) is not dict):
                    return self.error(400, request_id, -32602, 'Invalid initialization.')
                if len(self.sessions) >= 8: return self.error(503, request_id, -32000, 'Session capacity reached.')
                session_id = secrets.token_urlsafe(32)
                self.sessions[session_id] = Session(now, used={request_id})
                body = {'protocolVersion': PROTOCOL, 'capabilities': {'tools': {}}, 'serverInfo': {'name': 'Orivyn Workspace Companion', 'version': VERSION}}
                status, extra, response = self.result(request_id, body)
                extra['Mcp-Session-Id'] = session_id
                return status, extra, response
            session = self.sessions.get(headers.get('mcp-session-id'))
            if session is None: return self.error(404, request_id, -32000, 'Session unavailable.')
            session.touched = now
            if method == 'notifications/initialized' and request_id is None:
                if params: return self.error(400, None, -32602, 'Invalid notification.')
                session.ready = True
                return 202, {}, None
            if not session.ready: return self.error(409, request_id, -32000, 'Initialize the session first.')
            if method == 'notifications/cancelled' and request_id is None:
                if session.active_id == params.get('requestId') and session.cancelled: session.cancelled.set()
                return 202, {}, None
            if request_id is None: return self.error(400, None, -32600, 'Request ID required.')
            if request_id in session.used or len(session.used) >= 128:
                return self.error(409, request_id, -32000, 'Request ID reused or session request limit reached. Do not replay calls.')
            session.used.add(request_id)
            if session.active_id is not None: return self.error(409, request_id, -32000, 'A tool call is already active.')
            if method == 'tools/list':
                if params: return self.error(400, request_id, -32602, 'Pagination is not required by this catalog.')
                return self.result(request_id, {'tools': TOOLS})
            if method != 'tools/call': return self.error(400, request_id, -32601, 'Unsupported method.')
            try:
                if set(params) != {'name', 'arguments'}: raise CompanionError('Invalid tool call.')
                args = validate_arguments(params['name'], params['arguments'])
            except CompanionError:
                return self.error(400, request_id, -32602, 'Invalid tool or arguments.')
            cancelled = threading.Event()
            session.active_id = request_id; session.cancelled = cancelled
        try:
            # Request deadline and explicit cancellation share a read-only composite.
            cancellation = Cancellation(abort, cancelled)
            if cancellation.is_set(): raise safe_error()
            tool = params['name']
            if tool == 'companion.status': value = encode_json(self.workspace.status()).decode('utf-8')
            elif tool == 'workspace.list': value = encode_json(self.workspace.list_files()).decode('utf-8')
            elif tool == 'workspace.read': value = self.workspace.read(args['name'])
            else: value = encode_json(self.workspace.write(args['name'], args['text'], args['overwrite'], cancellation)).decode('utf-8')
            return self.result(request_id, {'content': [{'type': 'text', 'text': value}], 'isError': False})
        except CompanionError:
            return self.result(request_id, {'content': [{'type': 'text', 'text': str(safe_error())}], 'isError': True})
        finally:
            with self.lock:
                session.active_id = None; session.cancelled = None

    @staticmethod
    def result(request_id, body):
        return 200, {}, {'jsonrpc': '2.0', 'id': request_id, 'result': body}

    @staticmethod
    def error(status, request_id, code, text):
        return status, {}, {'jsonrpc': '2.0', 'id': request_id, 'error': {'code': code, 'message': text}}

    def authenticated(self, authorization):
        return hmac.compare_digest(authorization.encode('utf-8'), ('Bearer ' + self.token).encode('ascii'))


class Cancellation:
    def __init__(self, *events): self.events = events
    def is_set(self): return any(event.is_set() for event in self.events)


class LocalServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True
    block_on_close = True
    request_queue_size = 4
    allow_reuse_address = False

    def process_request(self, request, client_address):
        if not self.capacity.acquire(blocking=False):
            try:
                request.settimeout(0.1)
                request.sendall(b'HTTP/1.0 503 Service Unavailable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n')
            except OSError: pass
            finally: self.shutdown_request(request)
            return
        try: super().process_request(request, client_address)
        except Exception:
            self.capacity.release(); raise

    def process_request_thread(self, request, client_address):
        try: super().process_request_thread(request, client_address)
        finally: self.capacity.release()

    def handle_error(self, request, client_address):
        pass  # Never log untrusted paths, request content, credentials or exceptions.


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.0'  # One request per connection, no unbounded keep-alive.
    server_version = 'OrivynCompanion'
    sys_version = ''

    def handle(self):
        self.abort = threading.Event()
        def expire():
            self.abort.set()
            try: self.connection.shutdown(socket.SHUT_RDWR)
            except OSError: pass
        timer = threading.Timer(self.server.request_timeout, expire); timer.daemon = True; timer.start()
        self.connection.settimeout(self.server.request_timeout)
        try: super().handle()
        except (OSError, ValueError): pass
        finally: timer.cancel()

    def log_message(self, *args): pass

    def send_error(self, code, message=None, explain=None):
        self.respond(*Protocol.error(code, None, -32600, 'HTTP request refused.'))

    def respond(self, status, headers, body):
        raw = b'' if body is None else encode_json(body)
        if len(raw) > MAX_RESPONSE:
            status, headers, body = Protocol.error(500, None, -32000, 'Response exceeds the limit.')
            raw = encode_json(body)
        try:
            self.send_response(status)
            self.send_header('Content-Length', str(len(raw)))
            self.send_header('Connection', 'close')
            self.send_header('Cache-Control', 'no-store')
            self.send_header('MCP-Protocol-Version', PROTOCOL)
            if raw: self.send_header('Content-Type', 'application/json')
            for name, value in headers.items(): self.send_header(name, value)
            self.end_headers()
            if raw: self.wfile.write(raw)
        except (OSError, ValueError): pass

    def do_POST(self): self.request_mcp()
    def do_DELETE(self): self.request_mcp()
    def do_GET(self): self.respond(*Protocol.error(405, None, -32601, 'Only JSON POST and session DELETE are supported.'))

    def request_mcp(self):
        if self.path != '/mcp':
            return self.respond(*Protocol.error(404, None, -32600, 'Endpoint unavailable.'))
        critical = ['Authorization','Host','Content-Length','Content-Type','MCP-Protocol-Version','Mcp-Session-Id','Origin','Transfer-Encoding']
        if any(len(self.headers.get_all(key, [])) > 1 for key in critical) or sum(len(k) + len(v) for k,v in self.headers.items()) > 8192:
            return self.respond(*Protocol.error(400, None, -32600, 'Invalid headers.'))
        if self.headers.get('Host', '').lower() not in self.server.allowed_hosts or self.headers.get('Origin') is not None:
            return self.respond(*Protocol.error(403, None, -32600, 'Host or browser origin refused.'))
        if self.headers.get('Transfer-Encoding') is not None:
            return self.respond(*Protocol.error(400, None, -32600, 'Transfer encoding is unsupported.'))
        if self.command == 'POST' and self.headers.get('Content-Type', '').lower().split(';')[0].strip() != 'application/json':
            return self.respond(*Protocol.error(415, None, -32600, 'JSON content type required.'))
        length = self.headers.get('Content-Length', '0' if self.command == 'DELETE' else '')
        if not re.fullmatch(r'[0-9]{1,8}', length):
            return self.respond(*Protocol.error(411, None, -32600, 'Content length required.'))
        length = int(length)
        if length > MAX_BODY:
            return self.respond(*Protocol.error(413, None, -32600, 'Request exceeds the limit.'))
        headers = {k.lower(): v for k,v in self.headers.items()}
        # Authenticate before allocating or blocking on the request body.
        if not self.server.protocol.authenticated(headers.get('authorization', '')):
            return self.respond(*Protocol.error(401, None, -32001, 'Authentication required.'))
        raw = self.rfile.read(length)
        if len(raw) != length or self.abort.is_set(): return
        self.respond(*self.server.protocol.dispatch(self.command, headers, raw, self.abort))


def make_server(workspace, token, port=8765, request_timeout=5, public_host=None):
    if not 0 <= port <= 65535 or not 0.1 <= request_timeout <= 5: raise CompanionError('Invalid server bounds.')
    if public_host is not None and (type(public_host) is not str or len(public_host) > 253 or not re.fullmatch(r'[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?(?::[0-9]{1,5})?', public_host)):
        raise CompanionError('Invalid public Host allowlist value.')
    protocol = Protocol(workspace, token)
    server = LocalServer(('127.0.0.1', port), Handler)
    server.protocol = protocol; server.capacity = threading.BoundedSemaphore(4)
    server.request_timeout = request_timeout
    actual_port = server.server_address[1]
    server.allowed_hosts = {'127.0.0.1', 'localhost', f'127.0.0.1:{actual_port}', f'localhost:{actual_port}'}
    if public_host: server.allowed_hosts.add(public_host.lower())
    return server


def main(argv=None):
    parser = argparse.ArgumentParser(description='Bounded local Orivyn workspace companion. Not desktop control.')
    parser.add_argument('--workspace', required=True, type=Path)
    parser.add_argument('--token-file', type=Path)
    parser.add_argument('--init-token', action='store_true', help='Create a new private token exclusively, then exit.')
    parser.add_argument('--port', default=8765, type=int)
    parser.add_argument('--public-host', help='Exact HTTPS proxy Host header to allow, not a public bind address.')
    args = parser.parse_args(argv)
    workspace = None; server = None
    try:
        if os.name != 'posix' or os.getuid() == 0: raise CompanionError('Run as a dedicated non-root POSIX user.')
        workspace = Workspace(args.workspace)
        if args.init_token:
            create_token(args.token_file, args.workspace)
            print('Private token created. Transfer it securely; never include it in chat or logs.')
            return 0
        token = load_token(args.token_file, args.workspace)
        server = make_server(workspace, token, args.port, public_host=args.public_host)
        print('Orivyn companion running on localhost only. Use a trusted HTTPS proxy for phone access.')
        server.serve_forever()
    except CompanionError as error:
        print(str(error)); return 1
    except OSError:
        print('Local companion could not start or continue safely.'); return 1
    except KeyboardInterrupt:
        return 0
    finally:
        if server is not None: server.server_close()
        if workspace is not None: workspace.close()
    return 0


if __name__ == '__main__': raise SystemExit(main())
