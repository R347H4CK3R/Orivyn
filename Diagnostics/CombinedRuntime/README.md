# Combined native runtime (private development)

The app must link one llama runtime containing both reviewed bridges. This recipe
adds the native tool generation and vision C ABIs to the existing `llama` module;
linking a second copy of llama/ggml is unsupported. The stock b9049 release does
not contain these bridge symbols.

## Portable evidence

`build_host.sh PINNED_SOURCE STATIC_BUILD NEW_OUTPUT` links both bridges and the
same b9049 static archives into one Linux library, rejects unresolved symbols and
checks exported entry points and dynamic dependencies. Its SHA256SUMS preserves
inputs. It enables diagnostic cancellation probes only on this host build.
Linux linkage and generation do not verify Apple linking or iPhone memory use.

## Apple recipe (not yet executed)

Generate with `python3 Diagnostics/CombinedRuntime/prepare_build.py`. The input
upstream script must match its pinned SHA-256; modified upstream scripts fail.
Use a separate, clean llama.cpp checkout at
`2496f9c14965c39589f53eea31bdb6d762b1d360` and run the generated script from that
checkout on macOS, with `ORIVYN_BRIDGE_ROOT` set to the absolute reviewed app
checkout. The recipe builds device arm64 and simulator arm64/x86_64 for iOS 17,
combines static archives once per slice, and exports both bridge headers. The app
continues to require iOS 26; the framework target does not lower that requirement.

Before installing, run `python3 scripts/verify_combined_runtime.py PATH/llama.xcframework`
on macOS. Package the verified `llama.xcframework` at the zip root and record its
SHA-256. Opt into bootstrap with `ORIVYN_COMBINED_RUNTIME_ARCHIVE` and
`ORIVYN_COMBINED_RUNTIME_SHA256`; default bootstrap still uses the pinned official
release. A failed verification occurs before replacing the installed dependency.
For the private development package, set `ORIVYN_NATIVE_FEATURES` to
`ORIVYN_NATIVE_VISION ORIVYN_NATIVE_TOOLS` and run `scripts/ci_package_only.sh`
with the combined archive/hash variables. The script requires the archive for
these flags, passes them explicitly to xcodebuild, and records them in package
evidence. The sync probe is not activated by these flags.
No compiled Apple framework, successful app build, device acceptance, or release
readiness is implied by the recipe or its portable checks.
