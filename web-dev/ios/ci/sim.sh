#!/usr/bin/env bash
# sim.sh: drives the iOS Simulator for CI (GitHub's macOS runners; there is no Mac to look at).
#   sim.sh boot                       creates and boots an iPhone 16 on the runtime $SIM_OS names ("18", "26.5"; newest if unset)
#   sim.sh install <app>              installs the app (a fresh install: its data from an earlier one is removed first)
#   sim.sh run <name> <seconds> <until> [launch arguments...]
#                                     launches the app and, every $SHOT_EVERY seconds (default 10), takes a screenshot,
#                                     copies the app's Documents out (the debug log, the probe's result, the save mirror)
#                                     and prints the debug log's new lines; until the log has a line matching the regular
#                                     expression <until> ("" for none) or <seconds> have passed. RECORD=1 takes a video too;
#                                     SHOTS=0 takes no screenshots (simctl stalls while the game draws on a runner with
#                                     no graphics card: the app takes its own pictures then, -TsukiSnapshotEvery).
#                                     Exit 1 if <until> was given and never seen.
#   sim.sh memory-warning             sends the app a memory warning
#   sim.sh kill-web                   ends the page's WebKit content process, as iOS does when memory runs short
#                                     (in a run: MEMORY_WARNING_AT and KILL_WEB_AT, seconds after the launch)
#   sim.sh finish                     the simulator's own log for the app and WebKit, then shuts the simulator down
# Everything is written under $SIM_OUT (default web-dev/ios/build/ci). Every simctl call has a time limit and is
# announced with the time, so a log shows where a run stood when it stopped.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
out="${SIM_OUT:-$here/../build/ci}"
bundle="date.arcueid.tsukirebuild"
mkdir -p "$out"
udid_file="$out/udid"
udid="$(cat "$udid_file" 2>/dev/null || true)"

limit() { python3 "$here/with_timeout.py" "$@"; }
say() { echo "[$(date +%H:%M:%S)] $*"; }
container() { limit 20 xcrun simctl get_app_container "$udid" "$bundle" data 2>/dev/null; }
shot() {   # the simulator's picture is upright; the game is landscape
    [ "${SHOTS:-1}" = 1 ] || return 0
    limit 15 xcrun simctl io "$udid" screenshot --type=png "$1" >/dev/null 2>&1 || { say "screenshot failed or timed out: $(basename "$1")"; return 0; }
    sips -r "${SHOT_ROTATE:-270}" "$1" >/dev/null 2>&1 || true
}

case "${1:-}" in
boot)
    xcrun simctl list runtimes
    runtime="$(python3 "$here/pick_runtime.py" "${SIM_OS:-}")" || { echo "no iOS runtime matches '${SIM_OS:-}'" >&2; exit 1; }
    say "runtime: $runtime"
    udid="$(xcrun simctl create "Tsukihime CI" "iPhone 16" "$runtime")" || { echo "could not create an iPhone 16 on $runtime" >&2; xcrun simctl list devicetypes | grep -i iphone; exit 1; }
    echo "$udid" >"$udid_file"
    limit 300 xcrun simctl boot "$udid"
    limit 600 xcrun simctl bootstatus "$udid" -b
    xcrun simctl list devices | grep -F "$udid"
    ;;
install)
    limit 30 xcrun simctl terminate "$udid" "$bundle" >/dev/null 2>&1 || true
    limit 60 xcrun simctl uninstall "$udid" "$bundle" >/dev/null 2>&1 || true
    limit 120 xcrun simctl install "$udid" "$2" || exit 1
    say "installed $2"
    ;;
run)
    name="$2"; seconds="$3"; until="$4"; shift 4
    every="${SHOT_EVERY:-10}"
    limit 30 xcrun simctl terminate "$udid" "$bundle" >/dev/null 2>&1 || true
    recorder=""
    if [ "${RECORD:-0}" = 1 ]; then
        # (A background job of a script ignores SIGINT, which is how a recording is ended: the wrapper gives it back.)
        python3 -c 'import os, signal, sys; signal.signal(signal.SIGINT, signal.SIG_DFL); os.execvp(sys.argv[1], sys.argv[1:])' \
            xcrun simctl io "$udid" recordVideo --codec=h264 --force "$out/$name.mp4" >/dev/null 2>&1 &
        recorder=$!
        sleep 1
    fi
    say "launch: $*"
    limit 60 xcrun simctl launch "$udid" "$bundle" "$@" || say "launch failed or timed out"
    docs="$out/$name-documents"; rm -rf "$docs"
    seen=0; t=0; n=0; killed=0; warned=0; printed=0; started=$SECONDS
    echo "$name-$$" >"$out/phase"   # (a step that timed out can leave its script running: it stops when the next phase starts)
    if [ "${QUIET:-0}" = 1 ]; then
        # The game draws: the runner is too busy to answer simctl. The app was told when to quit (-TsukiQuitAfter).
        say "$name: leaving the app alone for ${seconds}s"
        sleep "$seconds"
        t="$seconds"
    fi
    while [ "$t" -lt "$seconds" ]; do
        sleep "$every"; t=$((SECONDS - started)); n=$((n + 1))
        [ "$(cat "$out/phase" 2>/dev/null)" = "$name-$$" ] || { say "$name: another phase has started; stopping"; exit 0; }
        say "$name: ${t}s"
        shot "$out/$name-$(printf %02d "$n").png"
        if [ -n "${MEMORY_WARNING_AT:-}" ] && [ "$warned" = 0 ] && [ "$t" -ge "$MEMORY_WARNING_AT" ]; then warned=1; "$0" memory-warning || true; fi
        if [ -n "${KILL_WEB_AT:-}" ] && [ "$killed" = 0 ] && [ "$t" -ge "$KILL_WEB_AT" ]; then killed=1; "$0" kill-web || true; fi
        c="$(container)"
        if [ -n "$c" ] && [ -d "$c/Documents" ]; then
            mkdir -p "$docs"; cp -R "$c/Documents/." "$docs/" 2>/dev/null || true
            log="$docs/Logs/debug.log"
            if [ -f "$log" ]; then
                total="$(wc -l <"$log" | tr -d ' ')"
                if [ "$total" -gt "$printed" ]; then
                    tail -n "+$((printed + 1))" "$log" | cut -c1-500 | tail -n "${LOG_LINES:-60}"
                    printed="$total"
                fi
                if [ -n "$until" ] && grep -Eq "$until" "$log"; then seen=1; say "seen after ${t}s: $until"; break; fi
            fi
        fi
    done
    sleep 2
    shot "$out/$name-end.png"
    limit 60 xcrun simctl terminate "$udid" "$bundle" >/dev/null 2>&1 || true
    if [ -n "$recorder" ]; then
        kill -INT "$recorder" 2>/dev/null
        for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$recorder" 2>/dev/null || break; sleep 1; done
        kill -KILL "$recorder" 2>/dev/null; wait "$recorder" 2>/dev/null
    fi
    c="$(container)"
    if [ -n "$c" ] && [ -d "$c/Documents" ]; then mkdir -p "$docs"; cp -R "$c/Documents/." "$docs/" 2>/dev/null || true; else say "the app has no data container: was it installed?"; fi
    if [ "${QUIET:-0}" = 1 ] && [ -f "$docs/Logs/debug.log" ]; then
        ls "$docs/Screens" 2>/dev/null | wc -l | xargs echo "pictures taken by the app:"
        grep -v "autopilot:" "$docs/Logs/debug.log" | cut -c1-500 | tail -n "${LOG_LINES:-120}"
    fi
    if [ -n "$until" ] && [ "$seen" = 0 ]; then echo "NOT SEEN within ${seconds}s: $until" >&2; exit 1; fi
    ;;
memory-warning)
    # What the Simulator's "Simulate Memory Warning" menu item sends.
    limit 20 xcrun simctl spawn "$udid" notifyutil -p UISimulatedMemoryWarningNotification </dev/null && say "memory warning sent"
    ;;
kill-web)
    # The page's process is a service of the simulator's own launchd; its pid is a process of this Mac.
    services="$(limit 20 xcrun simctl spawn "$udid" launchctl list </dev/null 2>/dev/null | grep -i "WebKit" || true)"
    echo "$services"
    victims="$(echo "$services" | awk '/com\.apple\.WebKit\.WebContent/ && $1 ~ /^[0-9]+$/ { print $1 }' | tr '\n' ' ')"
    [ -n "${victims// /}" ] || victims="$(pgrep -f "com.apple.WebKit.WebContent" | tr '\n' ' ')"
    [ -n "${victims// /}" ] || { echo "no WebContent process found" >&2; exit 1; }
    say "ending WebContent process(es): $victims"
    for pid in $victims; do kill -9 "$pid" 2>/dev/null || true; done
    ;;
finish)
    limit 120 xcrun simctl spawn "$udid" log show --last 40m --style compact \
        --predicate 'process == "Tsukihime" OR process CONTAINS "WebKit" OR process == "mediaserverd"' </dev/null 2>/dev/null | tail -c 8000000 >"$out/simulator-log.txt" || true
    ls -la "$out" | head -100
    limit 60 xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
    limit 60 xcrun simctl delete "$udid" >/dev/null 2>&1 || true
    ;;
*)
    echo "usage: sim.sh boot | install <app> | run <name> <seconds> <until> [args...] | memory-warning | kill-web | finish" >&2; exit 2 ;;
esac
