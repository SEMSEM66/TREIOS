#!/usr/bin/env python3
"""pick_runtime.py [version]: the identifier of an installed iOS Simulator runtime. Standard library only.

With a version ("18", "18.6", "26.5") the newest installed runtime whose version starts with it; with none, the newest
of all. Prints the identifier (com.apple.CoreSimulator.SimRuntime.iOS-26-5) and exits 1 if nothing matches.
"""
import json
import subprocess
import sys


def main():
    want = sys.argv[1] if len(sys.argv) > 1 else ""
    listing = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "runtimes", "-j"]))
    found = []
    for r in listing.get("runtimes", []):
        if not r.get("name", "").startswith("iOS"):
            continue
        if not r.get("isAvailable", False):
            continue
        version = r.get("version", "")
        if want and not (version == want or version.startswith(want + ".")):
            continue
        found.append((tuple(int(p) for p in version.split(".") if p.isdigit()), r["identifier"]))
    if not found:
        sys.exit(1)
    print(max(found)[1])


main()
