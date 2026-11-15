#!/usr/bin/env python3
"""Check XcodeGen's actual PBX graph (JSON from plutil), not a simulated merge."""
import argparse
import json
from pathlib import Path

def verify(data, peer, overlay):
    objects = data["objects"]
    remote = [v for v in objects.values() if v.get("isa") == "XCRemoteSwiftPackageReference"]
    actual = {v["repositoryURL"]: v["requirement"] for v in remote}
    expected = {v["url"]: {"kind": "revision", "revision": v["revision"]}
                for v in overlay["packages"].values()} if peer else {}
    assert actual == expected, (actual, expected)
    app = next(v for v in objects.values() if v.get("isa") == "PBXNativeTarget" and v.get("name") == "JarvisEVO")
    products = {objects[key]["productName"] for key in app.get("packageProductDependencies", [])}
    assert products == ({"LlamaRuntime", "X509", "SwiftASN1"} if peer else {"LlamaRuntime"}), products
    framework_phase = next(objects[key] for key in app["buildPhases"]
                           if objects[key]["isa"] == "PBXFrameworksBuildPhase")
    linked_products = {objects[objects[key]["productRef"]]["productName"]
                       for key in framework_phase["files"] if "productRef" in objects[key]}
    assert linked_products == products, (linked_products, products)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("graph")
    parser.add_argument("--peer", action="store_true")
    args = parser.parse_args()
    verify(json.loads(Path(args.graph).read_text()), args.peer,
           json.loads(Path("project-peer.json").read_text()))
    print("PASS: actual generated " + ("peer" if args.peer else "shipping") + " package graph")
