#!/usr/bin/env python3
"""build_ios_packs.py [--out DIR] [--part-mib N] [--verify]: web/assets as the parts the iOS app downloads. Standard library only.

The iOS app (web-dev/ios) does not carry the game's files: at 2.7 GB they are over what a release can hold in one file,
and a sideloaded app is installed again every week. It fetches them once, as parts of about 96 MiB:

  index.json            { format, id, totalBytes, fileCount, parts: [{ name, size, sha256, files: [{ p, s }] }] }
  assets-<hash>.part    the files of that part, one after another, in the order index.json lists them

A file's place in its part is the sum of the sizes before it; no file is split across parts. Nothing is compressed (the
files are AVIF, WebP, Opus and AV1 already). A part is named after its own SHA-256, so a part that comes out the same as
last time keeps its name and is neither uploaded nor downloaded again; each folder of web/assets starts a new part, so
a change in one folder leaves the other folders' parts as they were. `id` is the hash of the parts' hashes.

As in upstream's Android and desktop apps, the loose voices and sound effects (assets/voice, assets/se) are left out where the
sound packs (assets/pack) carry them. Writes to web-dev/ios/build/packs unless --out says otherwise; --verify reads the
parts back and checks every size and hash.
"""
import argparse
import hashlib
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.normpath(os.path.join(HERE, "../../web/assets"))
OUT = os.path.normpath(os.path.join(HERE, "../ios/build/packs"))
# What the game reads first comes first, so a download that is watched shows the small parts going by quickly.
ORDER = ["", "scripts", "sys", "fonts", "ui", "pack", "bgm", "img", "movie"]
BLOCK = 1 << 20


def groups(assets):
    """The files of web/assets by top folder ("" for the files at its top): [(folder, [(path, size)])], paths with "/"."""
    by = {}
    skip = {"voice", "se"} if os.path.isdir(os.path.join(assets, "pack")) else set()
    for root, dirs, files in os.walk(assets):
        dirs[:] = sorted(d for d in dirs if not d.startswith("."))
        rel = os.path.relpath(root, assets).replace(os.sep, "/")
        top = "" if rel == "." else rel.split("/")[0]
        if top in skip:
            dirs[:] = []
            continue
        for name in sorted(files):
            if name.startswith("."):
                continue
            path = name if rel == "." else f"{rel}/{name}"
            by.setdefault(top, []).append((path, os.path.getsize(os.path.join(root, name))))
    return sorted(by.items(), key=lambda g: (ORDER.index(g[0]) if g[0] in ORDER else len(ORDER), g[0]))


def plan(assets, limit):
    """The parts: lists of (path, size), each list's sizes adding up to `limit` at most unless one file alone is larger."""
    parts = []
    for _, files in groups(assets):
        part, used = [], 0
        for path, size in files:
            if part and used + size > limit:
                parts.append(part)
                part, used = [], 0
            part.append((path, size))
            used += size
        if part:
            parts.append(part)
    return parts


def build(assets, out, limit):
    os.makedirs(out, exist_ok=True)
    listed, total, count = [], 0, 0
    for n, part in enumerate(plan(assets, limit)):
        tmp = os.path.join(out, f"part-{n}.tmp")
        digest, size = hashlib.sha256(), 0
        with open(tmp, "wb") as w:
            for path, want in part:
                got = 0
                with open(os.path.join(assets, path), "rb") as r:
                    while True:
                        block = r.read(BLOCK)
                        if not block:
                            break
                        w.write(block)
                        digest.update(block)
                        got += len(block)
                if got != want:
                    raise RuntimeError(f"{path} changed size while it was read")
                size += got
        sha = digest.hexdigest()
        name = f"assets-{sha[:16]}.part"
        os.replace(tmp, os.path.join(out, name))
        listed.append({"name": name, "size": size, "sha256": sha, "files": [{"p": p, "s": s} for p, s in part]})
        total += size
        count += len(part)
    index = {
        "format": 1,
        "id": hashlib.sha256("".join(p["sha256"] for p in listed).encode()).hexdigest(),
        "totalBytes": total,
        "fileCount": count,
        "parts": listed,
    }
    with open(os.path.join(out, "index.json"), "w", encoding="utf-8") as f:
        json.dump(index, f, ensure_ascii=False, separators=(",", ":"))
    keep = {p["name"] for p in listed} | {"index.json"}
    for name in os.listdir(out):   # parts of an earlier build that this one no longer names
        if name not in keep and (name.endswith(".part") or name.endswith(".tmp")):
            os.remove(os.path.join(out, name))
    return index


def verify(out):
    """Reads every part back: its size and hash, and that its files' sizes add up to it. Returns the problems found."""
    index = json.load(open(os.path.join(out, "index.json"), encoding="utf-8"))
    wrong, seen = [], set()
    for part in index["parts"]:
        path = os.path.join(out, part["name"])
        if not os.path.isfile(path):
            wrong.append(f"{part['name']}: missing")
            continue
        digest = hashlib.sha256()
        with open(path, "rb") as f:
            for block in iter(lambda: f.read(BLOCK), b""):
                digest.update(block)
        if os.path.getsize(path) != part["size"] or digest.hexdigest() != part["sha256"]:
            wrong.append(f"{part['name']}: size or hash differs")
        if sum(f["s"] for f in part["files"]) != part["size"]:
            wrong.append(f"{part['name']}: its files do not add up to its size")
        for f in part["files"]:
            if f["p"] in seen or f["p"].startswith("/") or ".." in f["p"].split("/"):
                wrong.append(f"{f['p']}: listed twice, or not a path inside the assets")
            seen.add(f["p"])
    if index["fileCount"] != len(seen) or index["totalBytes"] != sum(p["size"] for p in index["parts"]):
        wrong.append("index.json: the totals do not match the parts")
    return index, wrong


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--assets", default=ASSETS)
    ap.add_argument("--out", default=OUT)
    ap.add_argument("--part-mib", type=int, default=96)
    ap.add_argument("--verify", action="store_true")
    args = ap.parse_args()
    if not args.verify:
        index = build(args.assets, args.out, args.part_mib << 20)
    index, wrong = verify(args.out)
    sizes = [p["size"] for p in index["parts"]]
    print(f"{index['fileCount']} files, {index['totalBytes']} bytes in {len(sizes)} parts (largest {max(sizes)}), id {index['id'][:16]}")
    for w in wrong:
        print("WRONG", w)
    if wrong:
        sys.exit(1)


if __name__ == "__main__":
    main()
