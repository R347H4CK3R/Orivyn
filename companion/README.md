# Orivyn Workspace Companion

A free, self-hosted **workspace file tool server**, not a virtual desktop. It works with Orivyn's explicitly reviewed remote-plugin calls and uses only Python's standard library.

## What really works

| Tool | Scope |
|---|---|
| `companion.status` | Workspace counts, byte limits and protocol version, without a host path |
| `workspace.list` | Up to 128 flat filenames and sizes |
| `workspace.read` | One UTF-8 text file, at most 64 KiB |
| `workspace.write` | Atomic UTF-8 write, at most 8 KiB; required explicit `overwrite` Boolean |

One dedicated workspace, maximum 8 MiB. Names must begin with an ASCII letter/digit, then contain only ASCII letters/digits, dots, hyphens or underscores, at most 128 characters. Nested folders, hidden files, symlinks, hardlinks, binary/NUL content, shell commands, browser automation, screen viewing/control, app access, arbitrary host files, email, remote models and credentials are **not supported**. Tool descriptions cannot grant permission. Nothing from your conversations is automatically sent.

This candidate was tested on Linux with real temporary files and authenticated localhost HTTP. Actual iPhone pairing, trusted HTTPS proxy deployment and macOS acceptance are **not yet verified**. It is a working bounded companion, not completion of the broader virtual-computer goal.

## Local setup

Requires Python 3.11+ on Linux or macOS, a regular non-root user and a local filesystem supporting POSIX directory descriptors, no-follow opens and atomic rename/link. Do not use a home directory, source checkout, network mount or a folder of existing personal files as the workspace. Run under a dedicated unprivileged account when possible. Keep the server code outside the workspace.

From the repository root:

```sh
mkdir -p "$HOME/OrivynWorkspace" "$HOME/.config/orivyn"
chmod 700 "$HOME/OrivynWorkspace" "$HOME/.config/orivyn"
python3 companion/orivyn_companion.py \
  --workspace "$HOME/OrivynWorkspace" \
  --token-file "$HOME/.config/orivyn/companion.token" --init-token
python3 companion/orivyn_companion.py \
  --workspace "$HOME/OrivynWorkspace" \
  --token-file "$HOME/.config/orivyn/companion.token"
```

Token creation is exclusive and never prints the token or replaces an existing file. Keep the generated token private and outside the repository/workspace. Transfer it to Orivyn's secure plugin token field through your own trusted local password manager/file handling, not a chat, screenshot, terminal history or support log. Orivyn saves it in device-only Keychain only when you explicitly enable Remember and install the connection.

Alternatively, set `ORIVYN_COMPANION_TOKEN` through a user-managed secret environment. It must be 32–128 URL-safe ASCII characters with sufficient randomness; do not use a sample token or put it in command-line arguments. The environment value takes precedence over `--token-file`. The server never automatically rotates, uploads or reveals credentials.

Startup binds **only `127.0.0.1:8765`**; `--port` changes the local port. There is no public-address binding flag. Stop with Ctrl-C. Stopping or disconnecting cannot undo writes already committed.

## HTTPS access from the phone

The iPhone requires a real trusted HTTPS endpoint. `http://127.0.0.1:8765/mcp` is local to the companion computer, not the iPhone, and is not a substitute for TLS.

Configure your own trusted HTTPS reverse proxy or Tailscale access separately. Do not disable certificate checks, forward the HTTP port to the internet, or install unknown certificates as a shortcut. Keep proxy and companion on the same trusted machine/network namespace. Restrict the endpoint to your devices, keep Bearer authentication, bound request size/time, and disable request-body/authorization logging. Audit proxy access logs separately; this program does not configure them.

Some proxies preserve the original `Host`. Explicitly allow **one exact** public hostname (optionally with its port):

```sh
python3 companion/orivyn_companion.py \
  --workspace "$HOME/OrivynWorkspace" \
  --token-file "$HOME/.config/orivyn/companion.token" \
  --public-host owner.example.ts.net
```

The hostname above is a placeholder, not a provided service. This adds a Host-header allowlist entry; it does not bind publicly, obtain a certificate or deploy a proxy. Alternatively configure your proxy to rewrite the upstream Host to `127.0.0.1:8765`, which is allowed by default. Any browser `Origin` header is rejected; this is not a web-page API.

In Orivyn: **Apps → Add plugin connection**, enter your approved `https://your-host/mcp` and token, connect, inspect the four schemas and install. Each call requires Review then Run. Example write arguments:

```json
{"name":"notes.txt","text":"Text I explicitly want to send","overwrite":false}
```

Read/list the workspace before retrying an uncertain write. Use `overwrite:true` only after reviewing the exact file and text. There is no delete tool, remote shell, OAuth flow or model-driven autonomous execution.

## Limits and failure semantics

- MCP `2025-06-18`, JSON POST responses only; initialization and initialized notification precede discovery. Session DELETE clears a connection, never files. GET/SSE streaming, resumption, resources, prompts, sampling and interactive server requests are unsupported.
- Eight 15-minute idle sessions. A session remembers up to 128 request IDs including initialization; then explicit reconnect is required. Reused IDs never repeat a tool. A fresh connection/new ID is a new action, so the app must not retry a lost response automatically.
- Four HTTP workers and a small backlog. Five-second absolute socket lifetime including slow headers/body, at most 32 KiB request body, 16 KiB arguments, 1 MiB response. Blocking OS filesystem calls cannot be forcibly rolled back by a socket deadline, but worker count remains bounded.
- Filesystem mutation is serialized. Writes use private temporary files and atomic no-clobber linking or explicit overwrite replacement. Cancellation is best effort before commit; a lost response does not imply a failed write. A disk error after commit can produce an uncertain result. Inspect the file before trying again.
- A crash may leave a hidden `.orivyn-…` temporary file. The service refuses an unsafe workspace rather than deleting evidence automatically. Stop it, inspect the temporary file locally and remove it yourself only after deciding it is safe.
- This is application-level confinement, **not an operating-system sandbox against the same user or root**. Do not permit unrelated processes to modify this directory during service operation. The token permits these four tools; anyone holding it can access this workspace. It is not a host-administration token.

For stronger deployment isolation, use a dedicated unprivileged account, or a rootless container with only this dedicated directory writable, application code read-only, memory/process/CPU limits, dropped capabilities, no host home/SSH/keychain/Docker socket mounts and no unnecessary egress. A container still needs a separately designed trusted proxy in its network namespace because the server only listens on loopback. No container or proxy deployment has been performed or accepted by these tests.

## Verification

```sh
python3 -W error::ResourceWarning -m unittest discover -s companion/tests -v
python3 -m py_compile companion/orivyn_companion.py
python3 -W error::ResourceWarning -m unittest discover -s scripts/tests
```

Tests use a temporary directory, non-live fixture credentials and local loopback only. No account, user computer, external provider or public endpoint is contacted. See `VERIFICATION.md` for observed results; `DESIGN.md` describes the trust boundary.
