#!/usr/bin/env python3
"""check_run.py <scenario> [ci dir]: what a simulator run of the iOS app left behind, checked. Standard library only.

Reads the debug logs, the compat probe's result and the pictures that sim.sh copied out of the app (web-dev/ios/build/ci),
prints one line per check, writes the same as a table to $GITHUB_STEP_SUMMARY, and exits 1 if a check that must hold
does not. The scenarios are the workflow's: `checkout` (the probe, then the game with a memory warning and an ended
page) and `download` (the packs fetched from the release, cut short once, then the game from them).

A simulator on a runner has no AV1 decoder: there the two AV1 rows of the probe are expected to fail, and that the
game goes on without its movies is one of the things checked.
"""
import glob
import json
import os
import re
import sys

rows = []


def check(name, ok, detail="", must=True):
    rows.append((name, "ok" if ok else ("FAIL" if must else "note"), str(detail)))
    return ok


def read(path):
    try:
        return open(path, encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        return []


def after_launch(lines):
    """The lines of the last launch in a log (a log runs on from one launch to the next)."""
    starts = [i for i, l in enumerate(lines) if "[app] launch," in l]
    return lines[starts[-1]:] if starts else lines


def perf(lines):
    """(frames a second, script, pc) of every perf line."""
    out = []
    for l in lines:
        m = re.search(r"perf: ([\d.]+) frames a second.*script (\S+), pc (\d+)", l)
        if m:
            out.append((float(m[1]), m[2], int(m[3])))
    return out


def game(ci, name="game"):
    docs = os.path.join(ci, f"{name}-documents")
    lines = after_launch(read(os.path.join(docs, "Logs", "debug.log")))
    check(f"{name}: the page loads from app://tsukihime.ios/", any("page loaded: app://tsukihime.ios/" in l for l in lines))
    page = next((l for l in lines if "[js:info] page app://tsukihime.ios/" in l), "")
    m = re.search(r"safe area ([\d.]+)px ([\d.]+)px ([\d.]+)px ([\d.]+)px", page)
    check(f"{name}: the page is a secure context and touch-first", "secure context true" in page and "touch-first true" in page, page[40:160])
    check(f"{name}: the page is told the safe area (Dynamic Island, home indicator)", bool(m) and float(m[2]) > 0 and float(m[3]) > 0,
          m[0] if m else "no page line")
    p = perf(lines)
    check(f"{name}: the story runs (the script moves on)", len(p) >= 2 and (p[-1][1], p[-1][2]) != (p[0][1], p[0][2]),
          ", ".join(f"{s} pc {pc} at {f:.0f} fps" for f, s, pc in p))
    errors = [l for l in lines if "[js:error]" in l]
    movies = [l for l in errors if "<video>" in l or "movie" in l]
    check(f"{name}: no errors from the page (a movie that cannot be decoded aside)", len(errors) == len(movies),
          "; ".join(l[25:200] for l in errors[:4]) or "none")
    missing = [l for l in lines if "[serve] 404" in l]
    check(f"{name}: no file asked for is missing", not missing, "; ".join(l.split("404 ")[-1] for l in missing[:6]) or "none", must=False)
    pictures = glob.glob(os.path.join(docs, "Screens", "*.jpg"))
    check(f"{name}: pictures taken by the app", len(pictures) >= 4, f"{len(pictures)} in {name}-documents/Screens")
    return lines


def checkout(ci):
    path = os.path.join(ci, "probe-documents", "Logs", "probe-result.json")
    try:
        doc = json.load(open(path, encoding="utf-8"))
    except (OSError, ValueError) as e:
        check("probe: a result was saved", False, e)
        doc = None
    if doc:
        device, probe = doc["device"], doc["probe"]
        check("probe: a result was saved", True, f"{device.get('modelName')}, {device.get('system')} ({device.get('systemBuild')}), {device.get('chip')}")
        state = {(r["group"], r["name"]): r for r in probe["results"]}
        failed = [f"{g} / {n}" for (g, n), r in state.items() if r["state"] == "fail"]
        expected = [f for f in failed if f.startswith("Movies / AV1")] if device.get("simulator") and not device.get("hardwareDecodeAV1") else []
        check("probe: nothing fails but AV1 where there is no AV1 decoder", sorted(failed) == sorted(expected), "; ".join(failed) or "nothing failed")
        check("probe: Ogg Opus decodes (voices, music, sounds)", probe.get("oggOpusDecodes") is True)
        for group, row in (("WebGL2", "context"), ("Pictures", "AVIF (a standing picture of the game)"), ("Serving", "byte range"),
                           ("Sound", "audio context without a tap"), ("Storage", "localStorage room")):
            r = state.get((group, row))
            check(f"probe: {group} / {row}", bool(r) and r["state"] == "ok", r["detail"][:150] if r else "no such row")
        h264 = state.get(("Movies", "fallback: H.264 (made by CI, 1080p): plays"))
        check("probe: a movie plays and seeks through the app's file serving (H.264)", bool(h264) and "played" in h264["detail"] and "seek to" in h264["detail"],
              h264["detail"][:150] if h264 else "no such row")
        check("probe: AV1", probe.get("av1Plays") is True, probe["verdicts"]["movies"], must=False)

    lines = game(ci)
    saved = any("memory warning: appSuspend -> saved" in l for l in lines)
    check("game: a memory warning makes the automatic save", saved)
    ended = next((i for i, l in enumerate(lines) if "content process ended" in l), None)
    check("game: the page's process ending is noticed", ended is not None)
    rest = lines[ended:] if ended is not None else []
    check("game: the page is loaded again with ?resume", any("loading app://tsukihime.ios/?resume" in l for l in rest) and any("page loaded: app://tsukihime.ios/?resume" in l for l in rest))
    before, then = perf(lines[:ended] if ended is not None else []), perf(rest)
    check("game: the story goes on from the save, not from the start",
          bool(before) and bool(then) and then[0][1] == before[-1][1], f"before: {before[-1][1:] if before else '-'}, after: {then[0][1:] if then else '-'}")
    check("game: the saves reach the mirror file", os.path.isfile(os.path.join(ci, "game-documents", "Saves", "localStorage.json")))

    # The story opened at a scene that starts with a movie (01_00_ARC01_1, command 54: TOMP 8).
    if os.path.isdir(os.path.join(ci, "movie-documents")):
        m = after_launch(read(os.path.join(ci, "movie-documents", "Logs", "debug.log")))
        refused = [l for l in m if "could not load <video>" in l or "passing it" in l]
        played = [l for l in m if "[js:info] movie " in l and "playing" in l]
        check("movie: the scene asks for its movie", bool(refused or played), (refused or played or ["no movie line in the log"])[0][25:170])
        check("movie: AV1 plays here", bool(played) and not refused, "it does not: the movie is passed over" if refused else "", must=False)
        lines = [l for l in m if "perf:" in l]
        p = perf(m)
        check("movie: the story goes on past it", bool(p) and p[-1][1] == "01_00_ARC01_1" and p[-1][2] > 54 and "movie none" in lines[-1],
              lines[-1][25:230] if lines else "no perf line")
        check("movie: pictures taken by the app", len(glob.glob(os.path.join(ci, "movie-documents", "Screens", "*.jpg"))) >= 3)


def download(ci):
    first = read(os.path.join(ci, "download-cut-short-documents", "Logs", "debug.log"))
    done = [l for l in first if re.search(r"\[download\] part \d+/\d+ in", l)]
    cut = next((l for l in first if "quitting in the middle of" in l), "")
    check("download: the first launch fetches from the release and is cut short in the middle of a part", bool(done) and bool(cut) and not any("[download] complete" in l for l in first),
          f"{len(done)} parts in; {cut[25:150]}")
    lines = after_launch(read(os.path.join(ci, "download-documents", "Logs", "debug.log")))
    resumed = next((l for l in lines if "going on from byte" in l), "")
    check("download: the second launch takes the cut part up where it stopped (HTTP Range)", bool(resumed), resumed[25:140])
    complete = next((l for l in lines if "[download] complete" in l), "")
    check("download: every part arrives and passes its checksum", "complete=true" in complete and not any("checksum" in l for l in lines), complete[25:170])
    check("download: the assets folder is excluded from backup", "excluded from backup=true" in complete)
    game(ci)


def main():
    scenario = sys.argv[1]
    ci = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "../build/ci")
    {"checkout": checkout, "download": download}[scenario](ci)
    for name, state, detail in rows:
        print(f"[{state}] {name}" + (f": {detail}" if detail else ""))
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write(f"### Simulator run: {scenario}, iOS {os.environ.get('SIM_OS', '?')}\n\n| Check | Result | Detail |\n| --- | --- | --- |\n")
            for name, state, detail in rows:
                f.write(f"| {name} | {state} | {detail.replace('|', '/')[:300]} |\n")
            f.write("\n")
    sys.exit(1 if any(state == "FAIL" for _, state, _ in rows) else 0)


main()
