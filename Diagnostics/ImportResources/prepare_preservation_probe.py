"""Create exact old source plus a clearly labeled experimental read-pool variant."""
import hashlib,json,pathlib,sys
root=pathlib.Path(__file__).resolve().parents[2];out=pathlib.Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=False)
source=(root/'JarvisEVO/Services/ArchivePreservation.swift').read_text()
(out/'baseline.swift').write_text(source)
assert source.count('try input.read(upToCount: chunk)')==1
assert source.count('try handle.read(upToCount: chunk)')==1
pooled=source.replace('try input.read(upToCount: chunk)','try autoreleasepool { try input.read(upToCount: chunk) }').replace('try handle.read(upToCount: chunk)','try autoreleasepool { try handle.read(upToCount: chunk) }')
(out/'read-pool-experiment.swift').write_text(pooled)
(out/'Driver.swift').write_bytes((root/'Diagnostics/ImportResources/PreservationProbe.swift').read_bytes())
(out/'source-manifest.json').write_text(json.dumps({p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in out.glob('*.swift')},indent=2)+'\n')
