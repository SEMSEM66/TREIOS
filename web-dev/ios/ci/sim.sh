#!/usr/bin/env bash
# sim.sh: drives the iOS Simulator for CI (GitHub's macOS runners; there is no Mac to look at).
#   sim.sh boot                       creates and boots an iPhone 16 on the runtime $SIM_OS names ("18", "26.5"; newest if unset)
#   sim.sh install <app>              installs the app (a fresh install: its data from an earlier one is removed first)
#   sim.sh run <name> <seconds> <until> [launch arguments...]
#                                     launches the app, takes a screenshot every $SHOT_EVERY seconds (default 10) and a
#                                     video, until the debug log has a line matching the regular expression <until>
#                                     ("" for none) or <seconds> have passed; then copies the app's Documents (the debug
#                                     log, the probe's result, the save mirror) out. Exit 1 if <until> was given and never seen.
#   sim.sh memory-warning             sends the app a memory warning
#   sim.sh kill-web                   ends the page's WebKit content process, as iOS does when memory runs short
#                                     (in a run: MEMORY_WARNING_AT and KILL_WEB_AT, seconds after the launch)
#   sim.sh finish                     the simulator's own log for the app and WebKit, then shuts the simulator down
# Everything is written under $SIM_OUT (default web-dev/ios/build/ci).
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
out="${SIM_OUT:-$here/../build/ci}"
bundle="date.arcueid.tsukirebuild"
mkdir -p "$out"
udid_file="$out/udid"
udid="$(cat "$udid_file" 2>/dev/null || true)"

container() { xcrun simctl get_app_container "$udid" "$bundle" data 2>/dev/null; }
debug_log() { local c; c="$(container)"; [ -n "$c" ] && echo "$c/Documents/Logs/debug.log"; }
shot() {   # the simulator's picture is upright; the game is landscape
    xcrun simctl io "$udid" screenshot --type=png "$1" >/dev/null 2>&1 || return 0
    sips -r "${SHOT_ROTATE:-270}" "$1" >/dev/null 2>&1 || true
}

case "${1:-}" in
boot)
    xcrun simctl list runtimes
    runtime="$(python3 "$here/pick_runtime.py" "${SIM_OS:-}")" || { echo "no iOS runtime matches '${SIM_OS:-}'" >&2; exit 1; }
    echo "runtime: $runtime"
    udid="$(xcrun simctl create "Tsukihime CI" "iPhone 16" "$runtime")" || { echo "could not create an iPhone 16 on $runtime" >&2; xcrun simctl list devicetypes | grep -i iphone; exit 1; }
    echo "$udid" >"$udid_file"
    xcrun simctl boot "$udid"
    xcrun simctl bootstatus "$udid" -b
    xcrun simctl list devices | grep -F "$udid"
    ;;
install)
    xcrun simctl terminate "$udid" "$bundle" >/dev/null 2>&1 || true
    xcrun simctl uninstall "$udid" "$bundle" >/dev/null 2>&1 || true
    xcrun simctl install "$udid" "$2"
    echo "installed $2"
    ;;
run)
    name="$2"; seconds="$3"; until="$4"; shift 4
    every="${SHOT_EVERY:-10}"
    xcrun simctl terminate "$udid" "$bundle" >/dev/null 2>&1 || true
    # (A background job of a script ignores SIGINT, which is how a recording is ended: the wrapper gives it back.)
    python3 -c 'import os, signal, sys; signal.signal(signal.SIGINT, signal.SIG_DFL); os.execvp(sys.argv[1], sys.argv[1:])' \
        xcrun simctl io "$udid" recordVideo --codec=h264 --force "$out/$name.mp4" >/dev/null 2>&1 &
    recorder=$!
    sleep 1
    echo "launch: $*"
    xcrun simctl launch "$udid" "$bundle" "$@"
    seen=0; t=0; n=0; killed=0; warned=0
    while [ "$t" -lt "$seconds" ]; do
        sleep "$every"; t=$((t + every)); n=$((n + 1))
        shot "$out/$name-$(printf %02d "$n").png"
        if [ -n "${MEMORY_WARNING_AT:-}" ] && [ "$warned" = 0 ] && [ "$t" -ge "$MEMORY_WARNING_AT" ]; then warned=1; "$0" memory-warning || true; fi
        if [ -n "${KILL_WEB_AT:-}" ] && [ "$killed" = 0 ] && [ "$t" -ge "$KILL_WEB_AT" ]; then killed=1; "$0" kill-web || true; fi
        log="$(debug_log)"
        if [ -n "$until" ] && [ -n "$log" ] && grep -Eq "$until" "$log" 2>/dev/null; then seen=1; echo "seen after ${t}s: $until"; break; fi
    done
    sleep 2
    shot "$out/$name-end.png"
    kill -INT "$recorder" 2>/dev/null
    for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$recorder" 2>/dev/null || break; sleep 1; done
    kill -TERM "$recorder" 2>/dev/null; wait "$recorder" 2>/dev/null
    c="$(container)"
    if [ -n "$c" ]; then
        rm -rf "$out/$name-documents"; cp -R "$c/Documents" "$out/$name-documents" 2>/dev/null || true
        echo "---- debug log ($name) ----"
        cat "$out/$name-documents/Logs/debug.log" 2>/dev/null | cut -c1-600 | tail -n "${LOG_TAIL:-150}"
        echo "---- end of debug log ----"
    else
        echo "the app has no data container: was it installed?" >&2
    fi
    if [ -n "$until" ] && [ "$seen" = 0 ]; then echo "NOT SEEN within ${seconds}s: $until" >&2; exit 1; fi
    ;;
memory-warning)
    # What the Simulator's "Simulate Memory Warning" menu item sends.
    xcrun simctl spawn "$udid" notifyutil -p UISimulatedMemoryWarningNotification && echo "memory warning sent"
    ;;
kill-web)
    # The page's process is a service of the simulator's own launchd; its pid is a process of this Mac.
    xcrun simctl spawn "$udid" launchctl list 2>/dev/null | grep -i "WebKit" || true
    victims="$(xcrun simctl spawn "$udid" launchctl list 2>/dev/null | awk '/com\.apple\.WebKit\.WebContent/ && $1 ~ /^[0-9]+$/ { print $1 }' | tr '\n' ' ')"
    [ -n "$victims" ] || victims="$(pgrep -f "com.apple.WebKit.WebContent" | tr '\n' ' ')"
    [ -n "$victims" ] || { echo "no WebContent process found" >&2; exit 1; }
    echo "ending WebContent process(es): $victims"
    for pid in $victims; do kill -9 "$pid" 2>/dev/null || true; done
    ;;
finish)
    xcrun simctl spawn "$udid" log show --last 30m --style compact \
        --predicate 'process == "Tsukihime" OR process CONTAINS "WebKit" OR process == "mediaserverd"' 2>/dev/null | tail -c 8000000 >"$out/simulator-log.txt" || true
    ls -la "$out" | head -80
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
    xcrun simctl delete "$udid" >/dev/null 2>&1 || true
    ;;
*)
    echo "usage: sim.sh boot | install <app> | run <name> <seconds> <until> [args...] | kill-web | finish" >&2; exit 2 ;;
esac
