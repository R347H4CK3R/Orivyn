# Native peer app integration design

The authenticated exchange has only been executed in a macOS host executable. The shipping iOS app excludes it and has no X509/SwiftASN1 package dependencies. Before connecting UI or scheduling, compile the existing tested exchange inside the actual iOS application for device and simulator with the same pinned certificate dependencies.

Use an isolated branch and compile-only feature flag. This does not generate pairing identities, trust network-provided pins, open listeners or enable sync. No release or IPA is created. The gate uses the pinned stock text runtime; combined vision/tool feature compatibility remains a later gate.

After this gate: implement and test iOS identity provisioning and explicit peer/scope consent; integrate receive ownership with the AppModel history lock and reload after every potentially committed receive, retaining drafts and attachments; then add foreground event-driven scheduling with bounded retries and revocation. Do not promise continuous iOS background execution. These later steps are not implemented by this compile gate.
