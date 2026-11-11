#!/usr/bin/env bash
# build_ipa.sh [--sim] [--device] [--no-debug-ui] [--asset-url URL]: the web port as an iPhone app, a thin shell
# around web/app (the game's assets are not inside: the app downloads them on first launch, see README.md).
#   --device       an UNSIGNED IPA for sideloading: build/Tsukihime-unsigned.ipa (the default when neither is given)
#   --sim          the app for the iOS Simulator: build/Tsukihime-sim.app
#   --no-debug-ui  without the debug menu and log viewer (the log file is written all the same)
#   --asset-url    where the app looks for the asset packs by default (the folder with index.json)
# Needs a Mac with Xcode and XcodeGen (brew install xcodegen). No signing identity, no Apple ID: Sideloadly or
# AltStore sign the IPA with yours when they install it.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
web="$(cd "$here/../../web" && pwd)"
sim=0; device=0; debug_ui=YES; asset_url="${TSUKI_ASSET_URL:-}"
while [ $# -gt 0 ]; do
    case "$1" in
        --sim) sim=1 ;;
        --device) device=1 ;;
        --no-debug-ui) debug_ui=NO ;;
        --asset-url) asset_url="$2"; shift ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done
[ "$sim" = 0 ] && [ "$device" = 0 ] && device=1

out="$here/build"
stage="$out/stage"
logs="$out/logs"
rm -rf "$stage"; mkdir -p "$stage" "$logs"

# What goes into the bundle. www is web/app untouched; native is this app's own pages, with the compat probe's test
# clips where make_probe_media.sh has made them.
cp -R "$web/app" "$stage/www"
cp -R "$here/App/Web" "$stage/native"
mkdir -p "$stage/native/media"
if [ -d "$out/probe-media" ]; then cp -R "$out/probe-media/." "$stage/native/media/"; fi
cp -R "$here/App/Assets.xcassets" "$stage/Assets.xcassets"
sips -s format png -z 1024 1024 "$web/app/apple-touch-icon.png" --out "$stage/Assets.xcassets/AppIcon.appiconset/icon-1024.png" >/dev/null
find "$stage" -name .DS_Store -delete

commit="$(git -C "$here" rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"
(cd "$here" && xcodegen generate --spec project.yml)

common=(-project "$here/Tsukihime.xcodeproj" -scheme Tsukihime -derivedDataPath "$out/dd"
        "TSUKI_GIT_COMMIT=$commit" "TSUKI_ASSET_URL=$asset_url" "TSUKI_DEBUG_UI=$debug_ui"
        "CURRENT_PROJECT_VERSION=$(date +%y%m%d%H%M)" COMPILER_INDEX_STORE_ENABLE=NO)

if [ "$sim" = 1 ]; then
    rm -rf "$out/sim.xcresult" "$out/Tsukihime-sim.app"
    set +e
    xcodebuild "${common[@]}" -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
        ARCHS=arm64 ONLY_ACTIVE_ARCH=NO -resultBundlePath "$out/sim.xcresult" build >"$logs/xcodebuild-sim.log" 2>&1
    status=$?
    set -e
    grep -E "error:|warning: unre|BUILD (SUCCEEDED|FAILED)" "$logs/xcodebuild-sim.log" | sort -u | head -80 || true
    [ "$status" = 0 ] || { echo "simulator build failed (full log: $logs/xcodebuild-sim.log)" >&2; tail -40 "$logs/xcodebuild-sim.log" >&2; exit 1; }
    cp -R "$out/dd/Build/Products/Debug-iphonesimulator/Tsukihime.app" "$out/Tsukihime-sim.app"
    du -sh "$out/Tsukihime-sim.app"
fi

if [ "$device" = 1 ]; then
    rm -rf "$out/device.xcresult" "$out/Payload" "$out/Tsukihime-unsigned.ipa"
    set +e
    xcodebuild "${common[@]}" -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
        CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
        -resultBundlePath "$out/device.xcresult" build >"$logs/xcodebuild-device.log" 2>&1
    status=$?
    set -e
    grep -E "error:|BUILD (SUCCEEDED|FAILED)" "$logs/xcodebuild-device.log" | sort -u | head -80 || true
    [ "$status" = 0 ] || { echo "device build failed (full log: $logs/xcodebuild-device.log)" >&2; tail -40 "$logs/xcodebuild-device.log" >&2; exit 1; }
    mkdir -p "$out/Payload"
    cp -R "$out/dd/Build/Products/Release-iphoneos/Tsukihime.app" "$out/Payload/"
    (cd "$out" && zip -qry -X Tsukihime-unsigned.ipa Payload)
    rm -rf "$out/Payload"
    ls -lh "$out/Tsukihime-unsigned.ipa" | awk '{print $5, $9}'
    unzip -l "$out/Tsukihime-unsigned.ipa" | tail -1
fi
