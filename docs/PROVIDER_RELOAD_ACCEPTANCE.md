# Provider descriptor refresh verification

A same-ID installed model could display a new title while its cached provider still held the old filename/hash/descriptor. Removed model IDs also remained in the private provider dictionary, exposing a removed provider if an old selection ID was restored.

The exact production reloadProviders, replaceProviders and selectedLocalAgentProvider accessor were extracted without rewriting into a Swift scaffold with explicit store, provider and platform doubles. Actual LocalModelDescriptor/catalog source was compiled unchanged. provider-reload-red compiled and failed three assertions. The production fix rebuilds the installed-provider dictionary and reuses a provider only when its complete descriptor matches. It preserves the shared engine and prunes removed IDs. provider-reload-green passed all five checks.

This proves the executed mapping logic, not full AppModel/SwiftUI, filesystem integration or inference. The static Swift linker's mktemp warning is retained in compile.log; execution exited zero. Native ProviderReloadTests uses actual LocalModelStore/AppModel metadata fixtures and asserts shared engine ownership, but is unexecuted until the Apple gate is available. It is included in the manual native gate. No model inference is asserted by these metadata fixtures.

No release or catalog changes were made.
