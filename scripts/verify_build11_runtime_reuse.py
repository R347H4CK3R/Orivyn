#!/usr/bin/env python3
"""Record exact-source runtime reuse without replacing any archive admission."""
import hashlib,json,subprocess,os
from pathlib import Path
SOURCE="03b9c5cc0f96e0dce332e0e3c36460a9346ff304"
RECIPE_SOURCE="f49c7558686046a16c66d29484ee953abefeb464"
def git(*args):
    return subprocess.check_output(["git",*args],text=True).strip()
head=git("rev-parse","HEAD")
# The exact integrated source passed host tests and iOS compile-only.
INTEGRATED="5c5ca7fbfe812386fb6afb8bc20778c374e0f525"
allowed={"project.yml", ".github/workflows/build11-candidate.yml",
 "scripts/verify_build11_runtime_reuse.py", "scripts/tests/test_build11_lineage.py"}
changed=set(git("diff","--name-only",INTEGRATED,head).splitlines())
assert changed<=allowed,sorted(changed-allowed)
before_project=git("show",INTEGRATED+":project.yml")
after_project=Path("project.yml").read_text().strip()
assert before_project.count("CURRENT_PROJECT_VERSION: 10")==1
assert before_project.replace("CURRENT_PROJECT_VERSION: 10","CURRENT_PROJECT_VERSION: 11",1)==after_project
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
output={"sourceRun":43685204421,"integrationRun":43722288003,"integrationCommit":INTEGRATED,"sourceCommit":SOURCE,"executedRecipeSource":RECIPE_SOURCE,
"packageSource":head,"cacheKey":os.environ["ORIVYN_RUNTIME_REUSE_CACHE_KEY"],"archiveSHA256":digest,"compiledInputGitBlobs":inputs,
"changedPaths":sorted(changed),"recipeDifference":"complete xcodebuild version capture only",
"scope":"Exact cache provenance only; ordinary archive/platform/symbol and IPA checks remain required."}
out=Path("artifacts/runtime-reuse");out.mkdir(parents=True,exist_ok=True)
(out/"provenance.json").write_text(json.dumps(output,indent=2)+"\n")
print(json.dumps(output,indent=2))
