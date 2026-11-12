#!/usr/bin/env bash
# publish_ipa.sh <tag> <ipa>: the unsigned IPA as an asset of the release that holds the asset packs, replacing the
# one before it, with a note of the commit and the run that built it. Needs gh and GH_TOKEN.
set -euo pipefail
tag="$1"; ipa="$2"
repo="${GITHUB_REPOSITORY:?}"
gh release upload "$tag" "$ipa" --clobber --repo "$repo"
gh release edit "$tag" --repo "$repo" --notes "The unsigned IPA and the asset packs of the iOS app, replaced by every push to the \`ios\` branch.

This build: commit ${GITHUB_SHA:-?}, run ${GITHUB_SERVER_URL:-https://github.com}/$repo/actions/runs/${GITHUB_RUN_ID:-?}.

How to install it without a Mac: README.md."
gh release view "$tag" --repo "$repo" --json assets --jq '.assets[] | select(.name | endswith(".ipa")) | "\(.name) \(.size) bytes"'
