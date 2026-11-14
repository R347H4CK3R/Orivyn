#!/usr/bin/env python3
"""Compile the actual SystemModelProvider snapshot loop against deterministic inputs.

Portable Unicode/delta regression, not an Apple FoundationModels or device test.
Only the incoming snapshot sequence and outgoing continuation are test doubles.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--source-root", type=Path, default=Path(__file__).resolve().parents[1])
args = parser.parse_args()
source = (args.source_root / "JarvisEVO/Providers/SystemModelProvider.swift").read_text()
start = '                    var previous = ""'
end = "                    continuation.finish()"
assert source.count(start) == 1 and source.count(end) == 1, "Snapshot loop changed; review extraction"
loop = source[source.index(start):source.index(end) + len(end)]
harness = r'''
import Foundation
enum ProviderError: Error { case invalidResponse, emptyResponse }
struct Snapshot: Sendable { let content: String }
struct Recorder: Sendable {
    var pieces: [String] = []
    var finished = false
    mutating func yield(_ value: String) { pieces.append(value) }
    mutating func finish() { finished = true }
}
func collect(_ inputs: [String]) async throws -> Recorder {
    let stream = AsyncThrowingStream<Snapshot, Error> { continuation in
        for input in inputs { continuation.yield(Snapshot(content: input)) }
        continuation.finish()
    }
    var continuation = Recorder()
    // PRODUCTION_LOOP
    return continuation
}
@main struct SnapshotSmoke {
    static func main() async throws {
        var failures: [String] = []
        var checks = 0
        func verify(_ condition: Bool, _ name: String) {
            checks += 1
            print("\(condition ? "PASS" : "FAIL"): \(name)")
            if !condition { failures.append(name) }
        }
        let valid: [(String, [String])] = [
            ("ordinary streaming and repeats", ["", "Hello", "Hello", "Hello!"]),
            ("combining acute accent", ["e", "e\u{301}", "e\u{301}!"]),
            ("multiple combining scalars", ["a", "a\u{301}", "a\u{301}\u{327}", "a\u{301}\u{327}b"]),
            ("emoji skin tone", ["👍", "👍🏽", "👍🏽!"]),
            ("emoji joiner across snapshots", ["👩", "👩\u{200D}", "👩\u{200D}💻", "👩\u{200D}💻!"]),
            ("regional indicator pair", ["🇺", "🇺🇸", "🇺🇸!"]),
            ("CRLF grapheme", ["line\r", "line\r\n", "line\r\nnext"]),
            ("mixed scripts and empty repeated prefix", ["", "", "漢", "漢字", "漢字é"])
        ]
        for (name, inputs) in valid {
            do {
                let result = try await collect(inputs)
                verify(result.finished && Array(result.pieces.joined().utf8) == Array(inputs.last!.utf8),
                       name + " preserves every byte")
                verify(!result.pieces.contains(""), name + " emits no empty delta")
            } catch { verify(false, name + " unexpectedly threw \(error)") }
        }
        let invalid: [(String, [String])] = [
            ("retraction", ["hello", "hell"]),
            ("replacement", ["cat", "car"]),
            ("prefix insertion", ["hello", "xhello"]),
            ("canonical encoding rewrite", ["é", "e\u{301}x"]),
            ("combining mark replacement", ["e\u{301}", "e\u{300}"])
        ]
        for (name, inputs) in invalid {
            do { _ = try await collect(inputs); verify(false, name + " must be rejected") }
            catch ProviderError.invalidResponse { verify(true, name + " rejected") }
            catch { verify(false, name + " wrong error \(error)") }
        }
        for inputs: [String] in [[], [""], ["", ""]] {
            do { _ = try await collect(inputs); verify(false, "empty output must fail") }
            catch ProviderError.emptyResponse { verify(true, "empty output rejected") }
            catch { verify(false, "empty output wrong error \(error)") }
        }
        print("\(checks - failures.count)/\(checks) checks passed")
        if !failures.isEmpty { exit(1) }
    }
}
'''.replace("// PRODUCTION_LOOP", loop)
with tempfile.TemporaryDirectory(prefix="orivyn-snapshot-") as directory:
    directory = Path(directory)
    main = directory / "SnapshotSmoke.swift"
    binary = directory / "snapshot-smoke"
    main.write_text(harness)
    subprocess.run(["swiftc", "-swift-version", "6", "-parse-as-library",
                    str(main), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
