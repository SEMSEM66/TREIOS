#!/usr/bin/env python3
"""check_assets_repo.py: run web-dev/tools/check_assets.py from a plain checkout. Standard library only.

check_assets.py reads two tables that are made from a game dump and stay on the machine that made them (web-dev/data is
gitignored): image_table.json, the names of the game's pictures, and ui_manifest.json, the interface art's list. A checkout
has neither, so the check cannot start there. Where one is absent this writes a stand-in made from what web/assets holds,
then runs the check unchanged. With a stand-in the pictures (or the interface art) are compared with themselves and so
always pass; the voices, sounds, music, movies, fonts, interface sounds, the fixed addresses in the code and the sound
packs are checked for real. It says which tables were stand-ins, and how many pictures the scripts name that web/assets
does not hold (some of those names are not in the game either; only the real table can tell them apart).
"""
import glob
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "../../.."))
A = os.path.join(ROOT, "web/assets")
DATA = os.path.join(ROOT, "web-dev/data")


def main():
    os.makedirs(DATA, exist_ok=True)
    stand_ins = []
    table = os.path.join(DATA, "image_table.json")
    if not os.path.isfile(table):
        json.dump(sorted(n[:-5] for n in os.listdir(os.path.join(A, "img")) if n.endswith(".avif")), open(table, "w"))
        stand_ins.append("image_table.json")
    manifest = os.path.join(DATA, "ui_manifest.json")
    if not os.path.isfile(manifest):
        packs = {}
        for d in sorted(glob.glob(os.path.join(A, "ui", "*", ""))):
            packs[os.path.basename(os.path.dirname(d))] = {n[:-5]: [0, 0] for n in sorted(os.listdir(d)) if n.endswith(".webp")}
        json.dump(packs, open(manifest, "w"))
        stand_ins.append("ui_manifest.json")
    try:
        code = subprocess.call([sys.executable, os.path.join(ROOT, "web-dev/tools/check_assets.py")])
    finally:
        for name in stand_ins:
            os.remove(os.path.join(DATA, name))
    if stand_ins:
        print(f"stand-in tables (made from web/assets, so their own check is not a real one): {', '.join(stand_ins)}")
    if "image_table.json" in stand_ins:
        named = set()
        for f in glob.glob(os.path.join(A, "scripts", "[0-9]*.json")):
            for o in json.load(open(f))["ops"]:
                if o[0] in ("STCH", "SCH2", "SPFC", "SPRD") and len(o) > 2 and o[2]:
                    named.add(o[2].upper())
        have = {n[:-5] for n in os.listdir(os.path.join(A, "img")) if n.endswith(".avif")}
        gone = sorted(named - have)
        print(f"pictures the scripts name: {len(named)}, of which not in web/assets/img: {len(gone)}" + (f", for example {gone[:8]}" if gone else ""))
    sys.exit(code)


main()
