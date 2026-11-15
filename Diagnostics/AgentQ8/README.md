# Existing Q8 text model diagnostic

Run the unchanged baseline decision prompt and grammar on all four frozen fixtures from AgentEvidenceCheck, using the already pinned and supported Qwen3-1.7B Q8_0 model instead of Q4_K_M. No evidence-check wrapper is used. All other inference settings and scoring remain unchanged.

The four Q4 baselines selected zero required reads. Determine whether the higher-precision existing model changes that failure. The previous missing-evidence wrapper is rejected (1/4 reads). Record every output; no policy, catalog, permissions or production inference code is changed. Single decisions do not prove full workflows. Workflow success only means four valid observations; target-read count determines this diagnostic's quality result.
