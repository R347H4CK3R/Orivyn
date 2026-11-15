import pathlib,json,urllib.request,hashlib,sys
root=pathlib.Path(sys.argv[1]);root.mkdir(parents=True,exist_ok=True)
manifest=json.loads(pathlib.Path("Diagnostics/VisionCandidate/MODEL_PAIR.json").read_text())
for item in manifest["artifacts"]:
    target=root/item["file"]
    url="https://huggingface.co/"+manifest["repository"]+"/resolve/"+manifest["revision"]+"/"+item["file"]
    digest=hashlib.sha256();size=0
    with urllib.request.urlopen(url,timeout=120) as response,target.open("wb") as output:
        assert response.status==200 and response.url.startswith("https://")
        while chunk:=response.read(1024*1024):
            size+=len(chunk)
            if size>item["size"]:raise ValueError("Oversized download")
            output.write(chunk);digest.update(chunk)
    assert size==item["size"] and digest.hexdigest()==item["sha"],"Model identity mismatch"
    print(item["file"],size,digest.hexdigest(),flush=True)
(root/"MODEL_PAIR.json").write_text(json.dumps(manifest,indent=2)+"\n")
