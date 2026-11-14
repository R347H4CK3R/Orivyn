# Remote inference completion reliability

Source review confirmed the HTTPS text provider previously ignored finish_reason. Partial output terminated by length/content_filter/tool_calls could reach [DONE], be saved as complete, and become eligible for voice read-aloud.

The parser now requires a supported stop before [DONE]. Length limits, policy stops, unsupported tools/functions/refusals, unknown reasons, duplicate terminal reasons, and content after stop fail explicitly with fixed redacted messages. No provider-supplied error text is echoed. Usage-only metadata after stop is allowed. Content in the same supported-stop chunk is preserved. This text-only endpoint does not execute tool requests. Existing error handling keeps prior partial output as failed and voice does not speak a failed provider response.

Compatibility: endpoints that omit finish_reason=stop are now rejected rather than advertised as a completed response. HTTPS, redirect refusal, bounded line/output sizes, cancellation and timeouts are unchanged. This is not universal SSE framing support or a new tool-execution implementation.

Six native regression methods added and the existing successful fixture updated to include stop. ProviderTests is now included in the explicit manual native gate. Native tests are not compiled/run here. Three portable source-contract checks observed missing guards fail before implementation and pass afterward; full portable suites pass (106 Python, 60 agent JavaScript, 39 VM JavaScript). They do not substitute for Swift/native/live-provider testing. No API credentials or user content sent externally, no paid CI, no release/catalog/version changes. A configured authorized endpoint and native execution remain required for live acceptance.
