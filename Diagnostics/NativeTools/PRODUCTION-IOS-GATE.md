# Required real iOS simulator native-tools gate

This gate calls the actual production `LocalAIProvider.suggestNativeReads` twice, with awaited `unload` between calls. It uses `LocalModelStore.verifiedURL`, the real engine-owned context/model, and the combined framework's native template/grammar/sampler/PEG bridge. It asserts both requested metadata reads. It does not execute tools or replace the explicit review/create/run flow.

Prepare one dedicated host directory using the existing immutable downloader:

```sh
export ORIVYN_NATIVE_TOOLS_MODEL_DIR="$RUNNER_TEMP/orivyn-native-tools"
python3 Diagnostics/NativeTools/download.py \
  --output "$ORIVYN_NATIVE_TOOLS_MODEL_DIR/Qwen3-1.7B-Q8_0.gguf"
```

The fixture is official Qwen3 1.7B Q8_0, revision `90862c4b9d2787eaed51d12237eafdfe7c5f6077`, SHA-256 `061b54daade076b5d3362dac252678d17da8c68f07560be70818cace6590cb1a`, 1,834,426,016 bytes. It fits the unchanged 2,000,000,000 byte cap. The existing 2.5-0.5B full-suite chat fixture remains unchanged.

After building the combined runtime, generating the main project and booting the explicitly selected simulator:

```sh
export ORIVYN_NATIVE_FEATURES='ORIVYN_NATIVE_VISION ORIVYN_NATIVE_TOOLS'
export NATIVE_TOOLS_DESTINATION="platform=iOS Simulator,id=$SIMULATOR_ID"
export NATIVE_TOOLS_DERIVED_DATA="$RUNNER_TEMP/orivyn-native-derived-data"
export NATIVE_TOOLS_EVIDENCE_DIR="$PWD/artifacts/native-tools-production"
bash Diagnostics/NativeTools/run_production_simulator.sh
```

Use the same DerivedData path as the vision gate/full tests. Run this gate, vision inference, and the full suite sequentially. Do not run both model gates concurrently on a 7 GB host. No large model is copied into the test bundle: the actual store uses the dedicated simulator-accessible host directory and verifies the full file before each request. This tests admission/inference/unload/reload, not import or installation. The store may set backup-exclusion metadata on its fixture root.

The runner temporarily injects `ORIVYN_REQUIRE_PRODUCTION_NATIVE_TOOLS=1` and the absolute model directory into the generated scheme's test environment, restores the scheme on exit, and rejects summary results unless exactly one test passed with no skips/failures. Under the required flag, missing fixture, missing native build flag, wrong platform, changed model admission, checksum failure or inference failure fails the test. Ordinary test runs without the explicit gate skip it and claim no native inference evidence.

Evidence includes the xcresult, actual per-pass assertions/attachments, source build log and host VM snapshots. Source validation on Linux is not native execution. Successful simulator execution still does not establish physical iPhone/Metal memory safety, broad model reliability, full UI execution or complete autonomy.
