# Offline calculator

Implemented a bounded deterministic arithmetic parser and explicit Calculator screen. The user reviews an expression and taps Calculate; no model inference, script engine, network or code evaluation is involved. Supports decimals, unary signs, + - * /, parentheses and common Unicode operator glyphs. Rejects unsupported syntax, divide-by-zero and nonfinite results. Bounds: 256 UTF-8 input bytes, 32 nested parentheses and 128 operations. Double values are approximate, clearly labeled.

Directly typed “Calculate 2 + 2” offers native review; quoted, negated and unrelated prose does not. Workspace/integration lists also expose the screen. Draft text is only prefilled, not automatically executed. Source capability metadata and chat tool guidance identify the screen.

The calculator API was initially absent (red compile evidence), then eight parser XCTest cases passed. Routing had three failing assertions before its pattern was added. Full normal Foundation run calculator-full-green-2 executes 267 tests with zero failures, including parser/routing cases. Python suite passes 134 tests after intentionally updating its exact tool-list assertion for Calculator.

Two test infrastructure failures are retained: disk-full discovery writes, and SwiftPM --disable-index-store discovery failure. Only superseded rebuildable caches were removed, original sources/manifests/logs/binaries preserved; normal complete rerun passes. The temporary change to an older proof's two routing source files was restored exactly before the new isolated proofs; its old logs were not reused for this verification.

Independent review caught an out-of-scope row helper call in IntegrationCatalogView; it was repaired to a query-filtered Label. Swift syntax parsing passes but Apple SDK typecheck and screen/device interaction remain unverified. Tests in the manual native gate are still pending. No release claim.
