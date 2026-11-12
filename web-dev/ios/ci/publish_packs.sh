#!/usr/bin/env bash
# publish_packs.sh <tag> <packs dir>: the asset packs (web-dev/tools/build_ios_packs.py) as assets of a release.
# Needs gh and GH_TOKEN. Only what the release does not have yet is uploaded: a part is named after its own hash, so
# one that is there already is the same part. Order: the new parts, then index.json, then the parts the new index no
# longer names are removed; a phone in the middle of a download finds every part its index names until the index is
# replaced, and reads the new index when a part has gone.
set -euo pipefail
tag="$1"; dir="$2"
[ -f "$dir/index.json" ] || { echo "no $dir/index.json" >&2; exit 1; }

if ! gh release view "$tag" >/dev/null 2>&1; then
    gh release create "$tag" --prerelease --target "${GITHUB_SHA:-HEAD}" --title "iOS: latest build" \
        --notes "The unsigned IPA and the asset packs of the iOS app, replaced by every push to the ios branch. See web-dev/ios/README.md."
fi

have="$(mktemp)"; want="$(mktemp)"
gh release view "$tag" --json assets --jq '.assets[].name' >"$have"
python3 -c 'import json, sys; print("\n".join(p["name"] for p in json.load(open(sys.argv[1]))["parts"]))' "$dir/index.json" >"$want"

new=()
while read -r name; do
    grep -qxF "$name" "$have" || new+=("$dir/$name")
done <"$want"
echo "parts: $(wc -l <"$want" | tr -d ' ') in the index, ${#new[@]} to upload"
if [ "${#new[@]}" -gt 0 ]; then
    gh release upload "$tag" "${new[@]}"
fi
gh release upload "$tag" "$dir/index.json" --clobber

{ grep '\.part$' "$have" || true; } | while read -r name; do
    if ! grep -qxF "$name" "$want"; then
        echo "removing $name (no longer in the index)"
        gh release delete-asset "$tag" "$name" --yes
    fi
done
echo "published: $(gh release view "$tag" --json url --jq .url)"
