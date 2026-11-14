# Orivyn companion: bounded workspace MCP server

## Purpose and approach
A free user-owned companion makes a few real desktop-adjacent tools available to Orivyn's manually reviewed plugin connection. It is not a virtual computer. This first implementation lists, reads and writes text files in one explicitly selected dedicated directory, plus reports bounded workspace status. It never runs shell commands, browses, opens apps, reads credentials, or interprets tool descriptions as instructions.

Chosen: Python 3.11+ standard library on POSIX Linux/macOS, no runtime package or paid service. A general MCP SDK would add dependencies and unneeded server capabilities. A generic shell/desktop bridge would widen permissions far beyond this safe first scope. Flat filenames intentionally avoid recursive host traversal; nested directories are unsupported rather than approximated.

## Interfaces and deployment boundary
`python3 companion/orivyn_companion.py --workspace /absolute/dedicated/directory --token-file /absolute/private/token --port 8765` opens only `127.0.0.1`. The directory must already exist and contain no unrelated data. `--init-token` creates a new 0600 token file exclusively; it never prints the token. Alternatively `ORIVYN_COMPANION_TOKEN` supplies a 32–128 character URL-safe secret. Tokens are not stored in the workspace or repository. No default, example, or generated secret is committed. Startup/error logs do not include tokens, request content, filenames, host paths or remote output.

A separately configured trusted HTTPS reverse proxy/Tailscale endpoint is required for the iPhone. The proxy must forward only `/mcp`, retain TLS, not log authorization/payloads, limit requests and not allow public unauthenticated access. This server neither configures that service nor disables the iOS TLS checks. Default localhost HTTP is transport behind that boundary, not a phone-accessible insecure endpoint. No public binding option is supplied.

## MCP and HTTP contract
- Pinned MCP `2025-06-18`, JSON POST only; `initialize`, `notifications/initialized` (202/empty), `tools/list`, `tools/call`, best-effort `notifications/cancelled`, session DELETE. GET/SSE/resumption/OAuth/server requests are unsupported with explicit errors.
- Every request requires constant-time Bearer authentication. Reject Origin headers (not a browser API), invalid Host (loopback defaults plus one explicitly configured --public-host for a proxy), query paths, transfer encoding, duplicate sensitive headers, missing/oversized Content-Length, wrong content type, duplicate JSON keys, invalid IDs/version/session and oversized/deep payloads. No cookie or CORS authentication.
- Eight random sessions, 15-minute idle expiry. One tool operation per session. Track 128 previously used request IDs per session; refuse new requests once exhausted rather than evict IDs and accidentally allow a side effect replay. New explicit initialization is required. Initialization is not a capability to execute anything until initialized notification arrives.
- At most four request threads, small socket backlog, 5-second absolute request lifetime including slow headers/body. Requests at capacity are closed with 503. Bodies are at most 32 KiB; tool arguments at most 16 KiB; JSON depth 16, object keys 64, arrays 128. Responses are capped below 1 MiB, no logs of data. Errors are fixed redacted messages.
- Exact output `content:[{type:text,text:...}], isError:bool` compatible with Orivyn. No output schema requirement, annotations are advisory only. No unsupported capability is advertised.

## Tools and filesystem boundary
- `companion.status({})`: protocol/server version, counts/bytes and supported limits; no host identity/path.
- `workspace.list({})`: sorted authorized filenames and sizes, maximum 128 entries.
- `workspace.read({name})`: UTF-8 text, at most 64 KiB.
- `workspace.write({name,text,overwrite})`: UTF-8 text up to 8 KiB, explicit Boolean overwrite required. Existing files are untouched unless overwrite is true. Output describes the committed write, not a fabricated desktop action.

Schemas require object roots, primitive string/Boolean fields and `additionalProperties:false`, within the phone's supported subset. Every call validates schema and exact argument bytes before opening files.

Only ASCII `[A-Za-z0-9][A-Za-z0-9._-]{0,127}` filenames, excluding hidden names, path separators, percent escapes and traversal components. No directories, symlinks, hardlinks, devices or sockets. Root is opened once using `O_DIRECTORY|O_NOFOLLOW`, verified canonical and owned by current user, not group/world writable. Every operation is relative to that directory descriptor. Files are opened `O_NOFOLLOW`, verified regular, same-device, single-link and user-owned; read/write counts are bounded. Existing unsafe entries cause refusal rather than hidden unsafe access. Maximum 128 files, 8 MiB aggregate, 64 KiB per file. Workspace mutations are serialized.

Writes create a random private temporary file inside the root, write/fsync completely, then atomic link-for-no-overwrite or replace-for-explicit-overwrite, followed by directory fsync. Failure before commit leaves original intact and removes its temporary file. Cancellation is checked before commit. A disconnect, deadline or cancellation can race with commit; it cannot undo a file already replaced. No automatic retry or duplicate replay. Crash-residual hidden temporary files are not auto-deleted: stop the service, inspect/remove manually before restarting.

This is application-level confinement, not a defense against the same OS user or root modifying process memory or racing directory contents. Use a dedicated unprivileged account or optional rootless container with only this directory mounted writable, read-only application code, no home/SSH/Docker socket mounts, dropped capabilities and no unneeded network egress. Never run as root. Container deployment is guidance, not performed by this task.

## Verification and honest limits
Tests use real temporary directories and authenticated HTTP loopback, not a real remote provider or personal files. Cases cover handshake/list/write/read, explicit overwrite, unsafe paths/symlinks/hardlinks, bounds, malformed/auth headers, origin/host denial, session expiry/replay, thread/deadline bounds, cancellation before commit and interrupted atomic writes. Native iOS contract tests remain separate. Real phone pairing, HTTPS proxy deployment, macOS acceptance, physical desktop/browser control and external account operations are unverified and out of this artifact's scope.
