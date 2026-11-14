# Required production vision simulator smoke

Prepared for the parent's authorized free standard GitHub macOS runner. Nothing
here dispatches CI, changes repository visibility, or invokes a paid runner.
Linux syntax/setup verification only so far: **this new XCTest has not run on
Apple**. The current earlier workflow cannot validate a test it does not contain.

## What actually runs

`JarvisEVOTests/ProductionVisionRuntimeTests/testRequiredProductionPNGInferenceAndRelease`
creates a 384×384 PNG containing a red square on white, then uses the real
production ImageIO boundary, VisionModelStorage (full pinned SHA256 verification),
VisionPairStore, NativeVisionRuntime, VisionWorker and combined C bridge. There
is no generated-RGB substitute, fake verified-path store, remote vision provider
or expected-answer insertion. The model question is only “Describe the visible
image in one sentence.” The actual answer must contain `red` and `square`.

The test awaits native close and reacquires/releases the pair through actual
verification to check ownership was released. It attaches the PNG and actual
answer/model hashes/timing to the xcresult. This is one inference/cleanup smoke,
not the nine-case Linux comparison, a general accuracy assertion, full AppModel
admission/UI automation, a heap-leak test, or physical iPhone acceptance.

Normal unit-test runs explicitly skip this expensive test unless
`ORIVYN_REQUIRE_PRODUCTION_VISION=1`. In required mode, missing/corrupt models,
missing native compile flag, wrong platform, decoding/load/output failures and
teardown failures FAIL. The runner additionally requires a completion marker
from the actual inference branch after xcodebuild succeeds, so failed environment
propagation cannot silently turn this required gate into a skipped pass.

## Prerequisites

- Existing Xcode 26-compatible generated `JarvisEVO.xcodeproj` / shared scheme.
- The combined `llama.xcframework` containing `ov_*` installed in the app package.
- `ORIVYN_NATIVE_VISION` on app **and test** targets. Preserve inherited `DEBUG`
  and other existing flags; this runner does not override compilation conditions.
- One existing booted simulator UDID chosen by the parent; no device targeting.
- Python 3 (standard library only), already installed Xcode tools, HTTPS model
  downloads allowed. No model is bundled in the app or copied into its resources.
- Dedicated writable host fixture folder. The production store can set its
  backup-exclusion metadata; model files are verified and never modified by test.

The two pinned assets total 1,984,906,336 bytes and each stays below the existing
2GB file cap. Setup checks space, bounded transfer size, a 15-minute aggregate
download deadline and full hashes; a corrupt existing file fails rather than
being silently replaced. It neither launches nor downloads during XCTest.
Model weights are public Apache-2.0 assets from pinned Hugging Face URLs; no
image/question upload occurs.

A sequential single CPU model with mapped weights is plausible on a 7GB host,
but **not established safe by Linux evidence**. The simulator, test host, Xcode
and OS also consume memory. Do not run this alongside text-model inference or
other model tests. The script records `hw.memsize` and host `vm_stat` before/after
(including failure) as context, not an app/phone peak-memory measurement. Capture
OOM, simulator termination or timeout as a real failure; do not switch to 500M,
increase limits, skip the required test, or call that successful validation.

## CI sequence after framework build, before full tests

Use the same generated project/configuration and absolute DerivedData directory
for this gate and the subsequent full suite so compilation can be reused. This
script calls `xcodebuild test`; it does not regenerate the project or framework.
Run the production vision and native-tools/model gates sequentially.

```yaml
- name: Prepare pinned production vision pair
  timeout-minutes: 16
  run: python3 Diagnostics/VisionProof/prepare_production_pair.py "$RUNNER_TEMP/orivyn-vision-pair"
- name: Required production vision simulator inference
  timeout-minutes: 15
  env:
    ORIVYN_VISION_MODEL_DIR: ${{ runner.temp }}/orivyn-vision-pair
    VISION_DESTINATION: platform=iOS Simulator,id=${{ env.SIMULATOR_ID }}
    VISION_DERIVED_DATA: ${{ runner.temp }}/orivyn-derived-data
    VISION_EVIDENCE_DIR: ${{ runner.temp }}/orivyn-production-vision-evidence
  run: bash Diagnostics/VisionProof/run_production_simulator.sh
```

The parent must expose its selected simulator ID as `SIMULATOR_ID` (or set the
literal destination directly); the example does not discover/boot one. Evidence
directory must be new. The runner temporarily injects required test environment
values into the **generated** scheme's TestAction, disables launch-environment
inheritance, then restores its exact original bytes through an EXIT trap. No
tracked project change is made. Run it without concurrent scheme mutation.

It selects only the named testcase, disables parallel execution and coverage,
and requests a 300-second default / 600-second maximum XCTest allowance. Upload
`VISION_EVIDENCE_DIR` with `if: always()` using the parent's existing artifact
step, including `.xcresult`, `xcodebuild.log`, and host-memory snapshots. Existing
fixture verification can be tested separately with the preparation command;
it does not imply Apple inference passed.
