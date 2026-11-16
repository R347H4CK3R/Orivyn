# Bounded chat tool routing candidate

## Implemented
- Directly typed existing exact commands for app information, installed models and saved-memory search automatically execute the native read on Send.
- The deterministic local-read provider returns bounded tool evidence into the normal persistent conversation lifecycle. It ignores model context, never invokes a language model, and never sends that evidence to a remote provider.
- The composer discloses the narrow local-read behavior before Send, including that the persisted result can enter later remote-model conversation context. Manual local-task review remains available.
- Connected Plugins now offer “Describe a task”: the selected inference provider receives only the submitted goal and live schemas, chooses one catalog tool, and proposes schema-validated arguments. Existing exact-call review remains mandatory before remote dispatch.
- Unsupported requests, malformed JSON, duplicate keys, unknown tool names, invalid arguments and oversized proposals fail closed. No plugin executable, endpoint, token, approval or missing identifier is invented.
- Catalog/provider changes, leaving the screen and backgrounding cancel proposal generation. Catalog identity is checked before showing a proposal.
- Existing MCP gate and journal remain responsible for single-use approval and uncertain remote outcomes.

## Scope and limits
This is not a complete multi-step ChatGPT-equivalent agent. Automatic ordinary-chat execution covers only the existing three exact typed intent forms, not arbitrary compound natural language or historical/imported instructions. Other local task plans still use their existing review flow. Plugin discovery requires a user-configured HTTPS MCP server; no universal store, arbitrary executable installation, or silent permission granting was added. Plugin proposal generation is in Plugins, not yet the main chat. Remote tool descriptions and “read-only” annotations are not trusted permission grants.

## Validation
Foundation Swift 6.0.3 production-source tests: 522 passed, zero failures, with the existing Linux URLProtocol redirect fixture excluded (Apple test still required). New proposal parser/generation tests and local-read adapter tests pass. Swift parser accepted changed UI/service files and git diff whitespace validation passed.

Three AppModel integration regressions were authored and syntax-parsed but not executed. Native SwiftUI typechecking, iOS application build, real-model proposal quality, physical device behavior, and real external server execution remain unverified. Do not publish this candidate as full acceptance or claim runtime parity.
