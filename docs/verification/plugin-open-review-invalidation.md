# Open exact-review revision invalidation native coverage

Three additional synthetic native UI tests cover an already-open plugin review:
conversation A→B→A, provider replacement, and catalog/connection reconnect.
Each opens the actual typed suggestion sheet, taps the existing exact Review
control, and asserts Run is enabled before any revision change. Run is never
tapped. Each then invokes a deterministic fixture-only toolbar action and
requires an explicit acknowledgment that the real revision changed and the
execution journal remained empty. The modal must disappear, no Run/card may
remain, and a fresh actor-backed transport count must still be zero.

Optional environment actions, their key, the fixture, and toolbar controls are
all DEBUG-only. Only the dual-flag plugin-suggestion fixture host supplies them;
the sheet also checks that exact fixture mode. No test controls ship in Release.
The action refuses to proceed without an actual prepared review and empty
journal. It uses actual model selection/provider replacement or the broker's
normal disconnect/connect/install methods, not assignments to revision fields.
Catalog testing also changes connection identity; it is not an isolated catalog
refresh test because the production broker has no catalog-only refresh API.

No time-delay assumption or background timer is involved. Screenshots and
hierarchies are retained before and after invalidation. Existing two suggestion
presentation tests remain unchanged. This is synthetic UI lifecycle coverage,
not proof of real-model selection quality or actual external server behavior.

Local source checks and Swift frontend parsing pass. Native typechecking and
interaction remain pending parent-owned CI; no CI or release was dispatched.

Final local run: 279 Python tests passed with one existing skip. Independent
source review found no blocking issue. Reconnect retains the same captured
synthetic client actor through the broker factory, so the counter covers calls
across connection instances. The reconnect case does not claim lasting restored
connection usability after modal teardown; it verifies revision invalidation.
