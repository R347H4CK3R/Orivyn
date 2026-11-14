# Integrated model-policy and complete-context checkpoint

This is unfinished development, not a release. The native Q8 suggestion gate passed on source bcf0e0e after earlier expiry failures; that variability is preserved, not labeled fixed. New phase metrics distinguish prefill, generation and cleanup. A separately pinned Q4 candidate is optional and admitted only after model identity verification; it does not change the default model or the 60-second native TTL.

The complete-context fix keeps all returned tool evidence in each fresh model call and stops explicitly if the 3,500-byte prompt budget is exceeded. Actual Q4 host tests still exposed premature answers without the requested conversation read. Structural regression success does not establish semantic autonomy. Raw failures are preserved under agent-complete-context-20261114.

Integrated verification at local source d08a119:
- Python: 198 tests, 197 passed, one dependency-specific skip.
- Foundation: 411 passed; the existing Linux URLProtocol redirect exclusion remains.
- Agent JavaScript: 119 passed.
- Catalog, VM and checksum-verified guest materialization passed.
- Independent review ran nine CI orchestration mocks successfully. Failed builds or skipped required tests cannot become a pass.
- Full run evidence: /workspace/scratch/8352eb8fe69c/orivyn-integrated-policy-context-checks/SUMMARY.json.

CI now runs real vision, original Q8 native suggestions, candidate Q4 native suggestions, and an actual LocalAgentSession search/read task sequentially with separate results and failure attachments. New Apple compilation/execution is pending. The new agent acceptance gate may fail on the known planner problem; it is intentionally not replaced by injected decisions.

Automatic two-device sync, reliable general autonomy, broad vision quality, physical iPhone performance and SideStore installation remain unverified or incomplete. No release, source-feed update or 1.0 completion is authorized by these test results.
