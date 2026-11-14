# Matching tool and agent result budgets

Native local conversation-search results allow up to20KiB encoded JSON, but the model-agent reducer stores/paginates only4096bytes per result. A bounded native-shaped ten-item control-heavy result was6172bytes and the actual reducer rejected it. This could fail a valid read before the model could use its results.

LocalToolResultBudget now fits whole prefix items to an explicit encoded-byte budget and includes resultTruncated=true and omittedItems when necessary. It never cuts JSON or edits retained items; oversized scalar metadata fails instead of disappearing. LocalAgentSession explicitly requests4096bytes. The independent deterministic read path keeps its existing larger budget via defaultnil and remains unchanged. Agent prompt requires describing a result as partial when flagged, but model compliance is not claimed.

Four real Swift tests pass: unchanged smallresult, escaped-byte prefix/omission integrity, oversized singleitem explicit emptyresult, invalidbudget/metadata rejection. Actual compiled Swift helper output passed directly into production JS reducer:3917bytes,7items kept,3omitted, result accepted and preserved exactly. Probe source/binary/output retained at /tmp/orivyn-tool-result-proof.swift, /tmp/orivyn-tool-result-proof and /tmp/orivyn-tool-result.json. Test-first missing-helper compilation is not claimed as old-code runtime regression; original mismatch was reproduced directly in JS with native-shaped data.

250Swift XCTest cases,134Python tests and70agentJS tests pass.192Swiftfiles syntax-parse. Independent review found no concrete defect. Native AppModel/tool/session integration and model answer correctness still require iOS/device tests. No release/catalog changes.
