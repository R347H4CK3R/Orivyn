#!/usr/bin/env python3
"""Record exact-source runtime reuse without replacing any archive admission."""
import hashlib,json,subprocess,os
from pathlib import Path
SOURCE="03b9c5cc0f96e0dce332e0e3c36460a9346ff304"
RECIPE_SOURCE="f49c7558686046a16c66d29484ee953abefeb464"
def git(*args):
    return subprocess.check_output(["git",*args],text=True).strip()
head=git("rev-parse","HEAD")
allowed={"Diagnostics/CombinedRuntime/prepare_build.py","scripts/tests/test_combined_recipe.py",
"scripts/ci_combined_runtime.sh","scripts/ci_macos.sh","scripts/ci_native_inference.sh",
".github/workflows/build10-candidate.yml","scripts/verify_build10_runtime_reuse.py"}
changed=set(git("diff","--name-only",SOURCE,head).splitlines())
assert changed<=allowed,sorted(changed-allowed)
inputs={}
for line in git("ls-tree","-r",SOURCE,"Diagnostics","scripts/verify_combined_runtime.py").splitlines():
    meta,path=line.split("\t",1)
    if (path.startswith("Diagnostics/NativeTools/") or path.startswith("Diagnostics/VisionProof/Bridge/")) and path.endswith((".cpp",".h")) or path in {
        "Diagnostics/CombinedRuntime/native-bridges.cmake","Diagnostics/CombinedRuntime/simulator-slices.sh",
        "Diagnostics/VisionRuntime/prepare_build.py","Diagnostics/VisionRuntime/source/build-xcframework.sh",
        "scripts/verify_combined_runtime.py"}:
        before=meta.split()[2]
        after=git("rev-parse",head+":"+path)
        assert before==after,path
        inputs[path]=before
assert len(inputs)>=8
old=git("show",RECIPE_SOURCE+":Diagnostics/CombinedRuntime/build-ios-combined.sh")
new=Path("Diagnostics/CombinedRuntime/build-ios-combined.sh").read_text().strip()
old_probe="XCODE_VERSION=$(xcrun xcodebuild -version 2>/dev/null | head -n1 | awk '{ print $2 }')"
new_probe="# Capture complete output: head can close the pipe while xcodebuild is writing.\n# Keep stderr visible so runner/tool failures remain diagnosable.\nXCODE_VERSION_OUTPUT=\"$(xcrun xcodebuild -version)\"\nprintf '%s\\n' \"$XCODE_VERSION_OUTPUT\"\nXCODE_VERSION=\"$(printf '%s\\n' \"$XCODE_VERSION_OUTPUT\" | awk 'NR == 1 { print $2 }')\""
assert old.count(old_probe)==1
assert old.replace(old_probe,new_probe,1)==new,"Recipe differs beyond diagnostic capture"
archive=Path(".cache/orivyn-combined/runtime.zip")
saved=Path(".cache/orivyn-combined/sha256.txt").read_text().strip()
with archive.open("rb") as stream:
    digest=hashlib.file_digest(stream,"sha256").hexdigest()
assert digest==saved=="fcb5fb0ac432cd962461dfd7214caf8a40fdd438bea2ef5f31422879ddf341e8"
output={"sourceRun":43685204421,"sourceCommit":SOURCE,"executedRecipeSource":RECIPE_SOURCE,
"packageSource":head,"cacheKey":os.environ["ORIVYN_RUNTIME_REUSE_CACHE_KEY"],"archiveSHA256":digest,"compiledInputGitBlobs":inputs,
"changedPaths":sorted(changed),"recipeDifference":"complete xcodebuild version capture only",
"scope":"Exact cache provenance only; ordinary archive/platform/symbol and IPA checks remain required."}
out=Path("artifacts/runtime-reuse");out.mkdir(parents=True,exist_ok=True)
(out/"provenance.json").write_text(json.dumps(output,indent=2)+"\n")
print(json.dumps(output,indent=2))
