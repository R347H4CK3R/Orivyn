"""Independent Python model only. NOT execution/proof of production Swift.
Replays seed 4 across 20,000 random streams against Python replacement decoding.
"""
import random


def incomplete_suffix_start(data):
    end = len(data)
    for index in range(end - 1, max(-1, end - 5), -1):
        lead = data[index]
        if 128 <= lead <= 191:
            continue
        expected = (2 if 194 <= lead <= 223 else 3 if 224 <= lead <= 239
                    else 4 if 240 <= lead <= 244 else 0)
        if not expected or end - index >= expected:
            return end
        if end - index >= 2:
            second = data[index + 1]
            if ((lead == 224 and second < 160) or (lead == 237 and second > 159)
                    or (lead == 240 and second < 144) or (lead == 244 and second > 143)):
                return end
        return index
    return end


rng = random.Random(4)
for _ in range(20_000):
    data = bytes(rng.randrange(256) for _ in range(rng.randrange(1, 50)))
    pending, output = b"", ""
    for byte in data:
        chunk = pending + bytes([byte])
        boundary = incomplete_suffix_start(chunk)
        output += chunk[:boundary].decode("utf8", "replace")
        pending = chunk[boundary:]
        assert len(pending) <= 3
    output += pending.decode("utf8", "replace")
    assert output == data.decode("utf8", "replace"), data
print("PASS: independent Python algorithm model, seed=4, streams=20000, pending<=3")
print("NOT production Swift execution; does not prove native runtime behavior.")
