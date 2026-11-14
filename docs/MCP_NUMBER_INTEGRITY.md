# Plugin numeric argument integrity

An actual compiled-production regression showed {"amount":-1e-400} underflowing to negative zero and passing a schema that requires a nonnegative integer. This changes a nonzero input before a reviewed tool call and can invalidate range checks.

The JSON parser now rejects nonzero significands that convert to zero. Genuine zero remains valid regardless of exponent spelling. Integral Double values outside ±9,007,199,254,740,991 are also rejected by shared value validation, closing a decimal/exponent notation bypass of the existing safe-integer bound. This intentionally rejects unsupported large integral number values/schemas rather than silently rounding them. Representable fractions and safe integral exponents remain supported. Numeric semantics remain IEEE-754, not arbitrary-precision decimal preservation.

Five new actual Swift tests were run before implementation: the full154-test suite had11 assertion failures demonstrating the underflow and exponent-bound bugs. After the fix all154 selected tests passed under official Swift6.1.3 Linux. Independent source review found no concrete new issue. Logs are retained in proof-12-red and proof-13-green. No real plugin service or credentials were used.

132Python/70agentJS/39VMJS also pass;179 Swift files syntax-parse. The existing Linux redirect-fixture exclusion and Observation linker blocker remain; iOS integration and release are still unverified. No paid CI.
