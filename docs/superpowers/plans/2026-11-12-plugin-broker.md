# Reviewed Plugin Broker Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement task by task with native gates. The user explicitly delegated ordinary design/engineering choices and requested autonomous continuation.

**Goal:** Install reviewed remote connections and execute one explicitly reviewed, schema-validated call with honest durable outcome tracking.
**Architecture:** Bounded transport/schema worker; main-thread observable broker with injected client, local persistence and separate Keychain credentials; native forms. Existing chat, models and conversation data stay unchanged.
**Tech Stack:** Swift 6, iOS 26, SwiftUI, URLSession, Security, atomic protected JSON files.
**Spec:** `docs/superpowers/specs/2026-11-12-plugin-broker-design.md` and `2026-11-12-mcp-client-design.md`.

## Global constraints
- No paid billing, proprietary service parity claims, downloaded executable plugins, automatic external disclosure or tool replay.
- Eight saved connections, 100 execution records, five-minute one-use review ticket, one live operation.
- Protocol and schema bounds exactly match the transport spec.
- Credentials never enter prompts/logs; save only with explicit Remember token choice.

## Review focus
- Cancel/background while server initialization completes: no stale session restore.
- Call may execute despite timeout/cancel: record unknown, never retry.
- Corrupt or unwritable local record: preserve bytes and block dispatch.
- Tool schema/catalog changes after review: invalidate rather than apply old approval.
- Private model context: never forwarded merely by opening a tool.

### Task 1: Transport and schema
- [x] Tests and spec authored before production.
- [ ] Observe actual `plugin.add` missing-control native RED.
- [ ] Implement only worker-owned Core/MCPTypes.swift, Core/MCPToolSchema.swift, Services/MCPHTTPClient.swift.
- [ ] Run contract tests including real URLSession receiving/redirect boundaries; inspect errors, not only test counts.

### Task 2: Permission broker and durable outcomes
Files: Core/PluginExecution.swift, Services/PluginBroker.swift, Services/PluginPersistence.swift, Services/PluginCredentialStore.swift, Tests/PluginBrokerTests.swift.
- [ ] Author tests for connection ownership, immutable one-use review, write-ahead records, unknown outcome recovery and no implicit model-context disclosure.
- [ ] Implement client injection using MCPHTTPClient as the production implementation, not fake runtime branches.
- [ ] Persist metadata/logs atomically with protected files; retain unreadable bytes; keep secrets in separate Keychain service.
- [ ] Run native tests, repair real failures, and review cancellation across every await.

### Task 3: Real plugin controls
Files: UI/PluginConnectionsView.swift, UI/WorkspaceViews.swift, UITests/PluginConnectionUITests.swift.
- [ ] Add explicit endpoint/token/connect/install, bounded schema display, JSON argument editor, exact call review and outcome log.
- [ ] Preserve draft/history/provider on navigation and cancel. Disable duplicate mutation during operations.
- [ ] Verify native invalid endpoint/no-call/cancel and actual configured server end-to-end only when an authorized endpoint is available.
- [ ] Update the 1.0.0 acceptance ledger; do not call configured tools, agent workflow, remote desktop or full computer verified without evidence.
