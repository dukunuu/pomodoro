#!/usr/bin/env python3
"""Diffs the QML reference dump against the Swift dump, ignoring int/float
representation. Exits non-zero and prints the first differences found."""
import json, sys

def norm(value):
    if isinstance(value, bool):
        return value
    if isinstance(value, float) and value.is_integer():
        return int(value)
    if isinstance(value, dict):
        return {k: norm(v) for k, v in value.items()}
    if isinstance(value, list):
        return [norm(v) for v in value]
    return value

def walk(a, b, path, out):
    if isinstance(a, dict) and isinstance(b, dict):
        for key in sorted(set(a) | set(b)):
            if key not in a:
                out.append(f"{path}.{key}: missing in reference")
            elif key not in b:
                out.append(f"{path}.{key}: missing in swift")
            else:
                walk(a[key], b[key], f"{path}.{key}", out)
    elif isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            out.append(f"{path}: length {len(a)} (reference) vs {len(b)} (swift)")
        for index, (x, y) in enumerate(zip(a, b)):
            walk(x, y, f"{path}[{index}]", out)
    elif a != b:
        out.append(f"{path}: {a!r} (reference) vs {b!r} (swift)")

reference = norm(json.load(open(sys.argv[1])))
swift = norm(json.load(open(sys.argv[2])))
differences = []
walk(reference, swift, "", differences)

if differences:
    print(f"{len(differences)} difference(s):")
    for line in differences[:40]:
        print("  " + line)
    sys.exit(1)
print(f"identical — {swift['sessionCount']} sessions, "
      f"{len(swift['days'])} days, {len(swift['weeks'])} weeks, "
      f"{len(swift['months'])} months compared")
