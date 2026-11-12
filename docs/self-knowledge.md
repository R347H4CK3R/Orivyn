# Bundled app self-knowledge

The provider prompt now includes a bounded, versioned `OrivynCapabilities.json` manifest plus the running bundle version, build and selected provider. This is conservative product metadata, not a source checkout. It does not expose credentials, automatically contact GitHub or claim access to the private repository. Missing, oversized or unsupported manifests fail closed without guessed capabilities.

This supports explanation and bug-report drafting. Autonomous repository inspection, repair, build and publication are **not implemented** by this change. Native VM and general visual understanding remain explicitly unavailable in product chat. Conditional features still require actual device availability, permissions, configuration and successful execution.

When shipping a changed capability, update the manifest only after its own verification. Runtime bundle version is read instead of hardcoding the target 1.0.0 as an achieved release.

Verification in this Linux environment: manifest tests failed before addition, then all 75 script tests passed. Native XCTest source and provider integration assertions are added but have not run here because Swift/Xcode is unavailable. The parent must run them in the next native simulator gate. No IPA or source publication was performed by this step.
