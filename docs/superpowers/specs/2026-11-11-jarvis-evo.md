# Jarvis-EVO implementation design

The owner explicitly delegated ordinary design, engineering and testing choices and requested immediate implementation. This is a separate native iOS 26+ iPhone app, not a rename of GhostAI/Jarvis. Original brand, no official OpenAI affiliation. Source is private until a deliberate verified release.

## Architecture

SwiftUI native navigation and conversation UI; SQLite durable local conversation/memory storage; Swift value types and testable state transitions; dependency-injected AIProvider streaming contract. Local downloaded open-weight inference is the required acceptance path, with optional Apple Foundation Models and explicit user-configured OpenAI-compatible endpoint. Do not send data to a remote endpoint until selected and configured by the user. Keys stay in Keychain. Plain-language capability/status reporting replaces simulated functionality.

## Chosen approach and alternatives

Use native SwiftUI plus a local model runtime. A web wrapper would weaken offline execution and iOS behavior. Foundation Models alone is insufficient because availability depends on device settings, language and system model readiness; it is an optional path rather than fulfillment of downloaded open-weight inference. A local GGUF/llama.cpp path offers broad models and permissive runtime licensing. The runtime dependency is selected after checking its current API and release integrity.

## State, privacy, errors

Every send saves the user message before inference; partial output is checkpointed and restored after interruption. Message states distinguish pending, streaming, complete, interrupted and failed. Switching conversations does not mix response ownership. Regeneration/edit creates branches or trims only with explicit UI. No remote sync by default. No credentials in export or diagnostics. Imports have limits and validate identifiers/content before replacing data. Attachments are copied into app-owned storage with safe names and size limits. No arbitrary app code execution or iOS permission bypass.

## Release gates

Real XCTest and UI test results, device ARM64 unsigned build, Mach-O/load-command and package verification, documented capability matrix. Downloaded inference and real-device SideStore verification remain distinct gates from a successful compile. Screenshots must be captured from the app, and fidelity comparison requires the owner's references (none accompanied the retrieved brief). No fake percentages, generated demo response presented as inference, or fabricated install evidence. Extended features are separately tracked until implemented and tested.
