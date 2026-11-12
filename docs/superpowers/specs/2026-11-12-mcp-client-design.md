# Bounded remote MCP client for Orivyn

## Scope and trust boundary

Installable plugins mean user-configured remote MCP connections, not downloaded executable iOS code. This layer supplies pure values, schema checking and HTTPS transport only. The integration owner supplies endpoint approval, per-call review, credential storage and UI. No real account or server is accessed during development. Server descriptions, results, schemas, instructions and annotations are untrusted data, never authority to connect, disclose data or execute another action. A tool's `readOnlyHint` does not grant approval.

Chosen approach: a small, explicitly bounded 2025-06-18 Streamable HTTP client. A full general-purpose SDK adds capabilities and lifecycle surface this app has not authorized; a fabricated local plugin response is not acceptable. No stdio process, OAuth enrollment, roots, sampling, elicitation, prompts/resources fetching, autonomous retries or downloaded code. No endpoint discovery from server content.

## Official protocol decisions

Verified against the official versioned specification on 2026-11-12:

- Initialize first, negotiate exactly `2025-06-18`, then send `notifications/initialized`. Advertise no optional client capabilities. Require the server's tools capability before discovery/calls.
- POST one JSON-RPC message; advertise JSON and SSE response support. Accept notification acknowledgements only as 202 with no body. Session IDs are optional. If assigned, send the session on subsequent requests; the protocol-version header also accompanies subsequent requests. Response headers need not echo either value, but conflicting supplied headers fail.
- A session 404 invalidates local state and requires explicit new initialization. Never replay a tool call as part of recovery. Close clears local state and attempts session DELETE; 405 means the server does not support explicit deletion, not that another action should be tried.
- Canceling a network task does not prove cancellation of a server effect. Best-effort `notifications/cancelled` is permitted only for a still-owned issued request, never initialize. Late replies cannot restore canceled state.
- Tools/list is paginated. Results distinguish protocol failure from a returned tool result with `isError`; neither a response nor a successful flag independently verifies the external effect.

Sources:
- https://modelcontextprotocol.io/specification/2025-06-18/basic/transports
- https://modelcontextprotocol.io/specification/2025-06-18/basic/lifecycle
- https://modelcontextprotocol.io/specification/2025-06-18/basic/utilities/cancellation
- https://modelcontextprotocol.io/specification/2025-06-18/server/tools

## Transport and bounds

Endpoint validation requires an explicit HTTPS URL, valid host and optional port 1–65535, maximum 4,096 bytes. Reject credentials, query, fragment, raw/decoded control characters and whitespace. User-owned LAN/Tailscale hosts are not categorically blocked, but this layer never grants a connection or local-network permission. Default TLS validation stays enabled; no self-signed bypass. Optional in-memory bearer token must be bounded and header-safe. Never persist/log tokens, session IDs, arguments or response bodies, or include them in error descriptions.

Use an ephemeral URLSession without cookies or credential storage. Reject every redirect, including same-origin redirects; never forward authentication to a redirect destination. Bound incoming bytes in the receiving transport before aggregation to 1 MiB, then independently check at the client boundary. Enforce an absolute 30-second request limit, JSON depth 32, schema depth 8, 64 properties per object, 128 array items, 32 tools, 8 discovery pages, 1,024-byte cursor/session ID, 128-byte tool name, 4,096-byte description, and 16 KiB serialized arguments. Failed validation sends nothing. One public operation is in flight; cancellation/close invalidates its token before cleanup. No automatic retry, even on an apparently transient failure.

SSE scope is finite bounded POST responses, including comments/notifications and a matching response. Parse UTF-8, CRLF/LF event framing and joined data lines; reject legacy endpoint events, wrong/duplicate response IDs, malformed frames and unsupported server requests. No unsolicited GET stream, Last-Event-ID replay or reconnection. Servers requiring interactive server-to-client requests before completing a POST are explicitly unsupported rather than silently treated as working. Supporting those requires an incremental bidirectional transport extension and a new test gate.

## Schema and content

Input and optional output schema roots must be objects. Supported validation keywords: type, properties, required, boolean additionalProperties, primitive enum, finite number/integer minimum/maximum/exclusive bounds, string minLength/maxLength, and homogeneous arrays/items/minItems/maxItems. Annotation-only title/description and a known JSON-schema dialect marker may be retained without interpretation. Unrecognized assertions, references, combinators, tuple arrays, formats, regex patterns and type unions are rejected, not ignored. Missing additionalProperties follows JSON Schema's true default; all values still obey global depth/size limits. String lengths use Unicode scalar counts, not Swift grapheme counts. Integer validation is limited to exactly representable safe integers; there is no silent numeric rounding. Nothing applies defaults or edits arguments.

Tool definitions are cached only after an entire valid, bounded discovery. Names are unique. A call must match a cached definition and pass its schema before any POST. Tool-list changes invalidate cached definitions; a call needs fresh discovery/review. Returned content supports bounded text and encoded images as inert values plus structuredContent. Unknown content types produce an explicit compatibility error; links/resources are never fetched. If a supported output schema is present, structured output is checked. Remote text is not injected as privileged instructions.

## Exact interfaces and ownership

Worker files: `Core/MCPTypes.swift`, `Core/MCPToolSchema.swift`, `Services/MCPHTTPClient.swift`, `Tests/MCPClientTests.swift`. No AppModel, UI, manifest, Keychain or identity edits.

```swift
MCPEndpoint.validated(_ text: String) throws -> MCPEndpoint // .url
MCPJSONValue // Codable, Sendable, Equatable: object/array/string/integer/number/bool/null
MCPToolSchema(json: MCPJSONValue) throws
MCPToolSchema.validate(_ value: MCPJSONValue) throws
MCPToolDefinition // name, title?, description?, inputSchema, outputSchema?, annotations?
MCPToolCallResult // content: [MCPContent], structuredContent?, isError
MCPContent // .text(String), .image(data: Data, mimeType: String)
MCPServerInfo // name, version
MCPClientFailure // code + effectMayHaveOccurred; redacted localizedDescription
actor MCPHTTPClient {
    init(endpoint: MCPEndpoint, bearerToken: String? = nil,
         transport: any MCPHTTPTransport = URLSessionMCPTransport()) throws
    func initialize() async throws -> MCPServerInfo
    func listTools() async throws -> [MCPToolDefinition]
    func callTool(named: String, arguments: MCPJSONValue) async throws -> MCPToolCallResult
    func cancelCurrentOperation() async
    func close() async
}
protocol MCPHTTPTransport: Sendable {
    func send(_ request: URLRequest, maximumResponseBytes: Int,
              timeout: TimeInterval) async throws -> MCPHTTPResponse
}
// MCPHTTPResponse: url, statusCode, headers, body
// URLSessionMCPTransport(configuration: URLSessionConfiguration = .ephemeral)
// privately copies and sanitizes configuration; URLProtocol injection is a native test boundary.
```

## Acceptance gates

Author tests before implementation; wait for actual missing `plugin.add` native UI RED. Contract tests inspect real JSON-RPC wire encoding and state through an injected transport, including success/error handshakes, optional session, wrong IDs/version/headers, JSON/SSE, schema rejection before send, pagination, byte/depth bounds, cancellation/late responses, close and no replay after an uncertain call. The real URLSession adapter additionally needs URLProtocol tests for redirect refusal and streaming byte/cancel enforcement. No test sends to a real account. Native compile/unit/UI gates precede delivery. Actual provider interoperability remains unverified until the owner approves and configures a real endpoint.
