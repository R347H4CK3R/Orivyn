# Frozen synthetic vision diagnostic

Run `python3 -B Diagnostics/VisionProof/QualityV1/run.py /absolute/vision.so /absolute/pinned-model-directory /absolute/results.json` with Python 3.11+ and an existing bridge library built by `../Linux/build.sh`. No downloads occur. The pair is hash-verified against MODEL_PAIR.json in the supplied model directory or the checked-in production manifest. Only rendered pixels and questions enter inference. The runner checks the unchanged frozen manifest before loading cases, writes all outputs and reports, and exits nonzero on any failed case.

RESULTS_LINUX.json records the existing library hash and production-pair diagnostic: 8/10 matched. Its library was not freshly rebuilt, so it does not prove latest-source or iOS correctness. The case02 direction and case08 count failures remain visible. `fixtures.py` can generate PNGs for visual review; PNGs are not required by the runner. No expectation, drawing instruction or case ID is sent to the model.
