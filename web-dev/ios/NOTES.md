# iOS port: notes

Findings, decisions and their reasons, kept current as the work goes. "Measured" means a CI run or a device report showed it; anything else is marked as an assumption or as **needs device**.

## The repository and what it costs

- `SEMSEM66/TREIOS` is **public** (GitHub API, 2026-11-11), and not marked as a fork.
- Standard GitHub-hosted runners are free and unlimited for public repositories, macOS included. If the repository were made private, macOS minutes would be billed at $0.062 a minute against the plan's included amount (about ten times the Linux rate), and a full run here uses three macOS jobs.
- Release assets are public downloads on a public repository: the app can fetch the asset packs with no token. On a private repository they would need one, and the packs would have to be hosted somewhere else.
- The game's assets are already public in this repository's tree; publishing them again as release assets changes nothing about who can read them.

## GitHub limits that decide the delivery (docs read 2026-11-11)

| Limit | Value | Source |
| --- | --- | --- |
| Release asset, per file | under 2 GiB | docs: About releases |
| Release assets per release | 1,000 | same |
| Release total size, bandwidth | no limit | same |
| Actions artifact storage (billed accounts, private repositories) | 500 MB Free, 1 GB Pro | docs: Actions limits |
| Artifact retention | 90 days by default | docs: workflow artifacts |
| Job time | 6 hours | docs: Actions limits |
| Concurrent macOS jobs | 5 | same |
| `ubuntu-24.04` (public) | 4 CPU, 16 GB RAM, 14 GB SSD | docs: GitHub-hosted runners |
| `macos-15`, `macos-26`, `xcode-27` | 3 CPU (M1), 7 GB RAM, 14 GB SSD | same |

`web/assets` in this repository is complete: 2.7 GB in 10,517 files, and `check_assets.py` reports nothing missing (see "Asset check" below for how it is run from a checkout).

## Decision: a thin IPA and downloaded asset packs

A fat IPA (the Android way, 2.8 GB) is not workable here:

- It is over the 2 GiB per-file limit of a release, so it could only live as an Actions artifact that expires.
- A free Apple ID signs for 7 days. Every week the whole IPA would be signed and installed again (Sideloadly sends it over USB or Wi-Fi; AltStore keeps its own copy on the phone and installs from it, so the phone would hold the game twice).
- Building it means copying 2.7 GB into the app on a runner with 14 GB of disk for every push.

So:

- **The IPA is thin**: the native shell and `web/app` (about 1.5 MB of web code). CI publishes it on every push to `ios`.
- **The assets are packs**: `web/assets` cut into parts of about 96 MiB, each a plain concatenation of files, and an `index.json` that lists every part (name, size, SHA-256) and every file (path, size, part, offset). No archive format, no third-party code to read it. CI publishes them as release assets.
- **The app downloads them on first launch** into `Library/Application Support/assets`: one part at a time, resumable (HTTP `Range` onto the partly downloaded file), each part checked against its SHA-256, extracted and deleted before the next one starts, so the phone needs the size of the game plus one part. The folder is excluded from iCloud backup. The source address is in the app's settings screen and can be changed.
- A part is named after its own hash, so a part that has not changed between two builds is never fetched or uploaded twice.
- After the download the game makes no connection. The assets are in the app's data container, which iOS keeps across updates and re-signing as long as the bundle ID stays the same (the same Apple ID with the same tool keeps it the same).

## How the game is served: `app://tsukihime.ios/`

The desktop app uses `app://tsukihime.desktop/`; the iOS app does the same with a `WKURLSchemeHandler`. `home.js` gets the one host added to `APP_HOSTS`, so the app opens on the game and not on the site's opening page (the only change to `web/app` so far).

## Runners and Xcode (runner-images READMEs read 2026-11-11)

| Label | macOS | Xcode used | Simulator used |
| --- | --- | --- | --- |
| `macos-15` | 15.8 | 26.3 | iPhone 16, iOS 18.6 (the oldest 18.x installed; no 18.0 runtime on any image) |
| `macos-26` | 26.7 | 26.6 (builds the IPA) | iPhone 16, iOS 26.5 |
| `xcode-27` (public preview image) | 27.0 | 27.2 | iPhone 16, iOS 27.2 |

## Asset check

`web-dev/tools/check_assets.py` reads `web-dev/data/image_table.json` and `ui_manifest.json`, which are made from a game dump and are gitignored, so it cannot start in a checkout. `web-dev/ios/ci/check_assets_repo.py` writes stand-ins from what `web/assets` holds, runs the check unchanged and removes them. With stand-ins, pictures and interface art are compared with themselves (not a real check); voices, sounds, music, movies, fonts, interface sounds, fixed addresses in the code and the sound packs are checked for real.

Measured here on 2026-11-11: images 8903, voices 16460, sounds 1284, music 128, movies 45, interface art 212, sound packs 658, nothing missing. The scripts name 7,331 pictures, one of which (`26`) is not in `web/assets/img`; without the real table it cannot be told whether the game has it.

## Compatibility matrix

Nothing measured yet. Filled in from the compat probe (CI simulators, then the iPhone 16).

## Needs device

Listed as they come up.
