# App dependency graphs

The default project.yml contains only the local LlamaRuntime package. Peer certificate generation is compiled behind ORIVYN_PEER_TLS_SPIKE and must not force every shipping UI, inference and packaging build to compile swift-certificates and its crypto dependencies.

Use python3 scripts/generate_project.py for app project generation. It selects project-peer.json only when ORIVYN_NATIVE_FEATURES contains the exact ORIVYN_PEER_TLS_SPIKE token, or when the isolated peer gate passes --peer. The overlay includes project.yml additively, retaining every app source, resource, target, scheme and existing dependency. It adds X509 and SwiftASN1 and retains all three exact package revision pins. Peer authentication notices remain unchanged.

The isolated ci_peer_app.sh gate still builds both iOS and iOS Simulator with the SPI flag and validates Package.resolved against those revisions. Standalone Diagnostics/PeerAuthentication remains independent. When enabling SPI in another generation script, use the helper before xcodebuild and pass the same feature flag to xcodebuild.

The project-graph workflow checks the actual XcodeGen PBX graphs in both modes, then compiles the SPI-off app and test targets against the iOS SDK with stock LlamaRuntime. This is compile evidence only; it does not execute tests, exercise peer transport, validate combined native inference or prove device acceptance. The portable unittest checks selector behavior, subprocess failure propagation and pinned overlay content; it does not run XcodeGen.
