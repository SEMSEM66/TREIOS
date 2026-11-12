# iOS port: notes

Findings, decisions and their reasons, kept current as the work goes. "Measured" means a CI run or a device report showed it; anything else is marked as an assumption or as **needs device**.

## The repository and what it costs

- `SEMSEM66/TREIOS` is **public** (GitHub API, 2026-11-11), and not marked as a fork.
- Standard GitHub-hosted runners are free and unlimited for public repositories, macOS included. If the repository were made private, macOS minutes would be billed at $0.062 a minute against the plan's included amount (about ten times the Linux rate); a full run here uses about 30 macOS minutes per simulator version.
- Release assets are public downloads on a public repository: the app fetches the asset packs with no token (measured: `index.json` answers 200 and a `Range` request 206, through the redirect to `release-assets.githubusercontent.com`). On a private repository they would need a token, and the packs would have to be hosted somewhere else.
- The game's assets are already public in this repository's tree; publishing them again as release assets changes nothing about who can read them.
- Upstream's `deploy-cloudflare.yml` runs on pushes to `main` only. It did not run for any push to `ios`. It will run (and fail, with no secrets) when `ios` is merged into `main`, unless it is disabled in the repository's Actions settings first.

## GitHub limits that decide the delivery (docs read 2026-11-11)

| Limit | Value | Source |
| --- | --- | --- |
| Release asset, per file | under 2 GiB | docs: About releases |
| Release assets per release | 1,000 | same |
| Release total size, bandwidth | no limit | same |
| Actions artifact storage (billed accounts, private repositories) | 500 MB Free, 1 GB Pro | docs: Actions limits |
| Artifact retention | 90 days by default (30 set here) | docs: workflow artifacts |
| Job time | 6 hours | docs: Actions limits |
| Concurrent macOS jobs | 5 | same |
| `ubuntu-24.04` (public) | 4 CPU, 16 GB RAM, 14 GB SSD | docs: GitHub-hosted runners |
| `macos-15`, `macos-26`, `xcode-27` | 3 CPU (M1), 7 GB RAM, 14 GB SSD | same |

Measured on the runners: `macos-26` reports "Apple M1 (Virtual)", 3 CPUs, 7 GB, and 92 GB free on a 320 GB disk (far more than the 14 GB the docs promise). `web/assets` in this repository is complete: 2.7 GB in 10,517 files (see "Asset check").

## Decision: a thin IPA and downloaded asset packs

A fat IPA (the Android way, 2.8 GB) is not workable here:

- It is over the 2 GiB per-file limit of a release, so it could only live as an Actions artifact that expires.
- A free Apple ID signs for 7 days. Every week the whole IPA would be signed and installed again (Sideloadly sends it over USB or Wi-Fi; AltStore keeps its own copy on the phone and installs from it, so the phone would hold the game twice).
- Building it means copying 2.7 GB into the app on a runner for every push.

So:

- **The IPA is thin**: the native shell, `web/app` and the probe's test clips. Measured: 10.2 MB. CI publishes it on every push to `ios`.
- **The assets are packs**: `web/assets` cut into parts of at most 96 MiB, each a plain concatenation of files, and an `index.json` that lists every part (name, size, SHA-256) and the files in it (path, size). No archive format, no third-party code to read it. Measured: 35 parts, 2,797,198,712 bytes, 10,517 files, built in 9 s; CI publishes them as assets of the release `ios-latest`.
- **The app downloads them on first launch** into `Library/Application Support/assets`: one part at a time, resumable (HTTP `Range` onto the partly downloaded file), each part checked against its SHA-256, extracted and deleted before the next one starts, so the phone needs the size of the game plus one part. The folder is excluded from iCloud backup. The source address can be changed on the download screen.
- A part is named after its own hash, and each folder of `web/assets` starts a new part, so a part that has not changed between two builds is neither uploaded nor downloaded again (measured: a second CI run with the same assets uploaded nothing).
- After the download the game makes no connection. The assets are in the app's data container, which iOS keeps across updates and re-signing as long as the bundle ID stays the same (the same Apple ID with the same tool keeps it the same). **needs device**: that a re-signed install really keeps them.

## How the game is served: `app://tsukihime.ios/`

The desktop app uses `app://tsukihime.desktop/`; the iOS app does the same with a `WKURLSchemeHandler`. Measured in the simulator (iOS 26.5): the page is a secure context, `localStorage` works (about 4.75 million characters of room), ES modules and `fetch` load, byte ranges are answered with 206 and the right bytes, and an H.264 `<video>` plays and seeks through it. So the loopback HTTP server that was the fallback plan is not needed and was not built.

## Changes to `web/app`

Two, both additive:

- `home.js`: `tsukihime.ios` added to `APP_HOSTS`, so the app opens on the game and not on the site's opening page.
- `main.js`: `?resume` in the address goes straight to the newest save (what Continue loads) instead of the logo and the title. The app uses it for the reload that follows an ended page process. No page of the website has it in its address.

Everything else iOS needs is in `bridge.js`, which the app injects and `web/app` does not know of. The 521 engine tests pass with these changes.

## Runners and Xcode (runner-images READMEs read 2026-11-11)

| Label | macOS | Xcode used | Simulator used |
| --- | --- | --- | --- |
| `macos-15` | 15.8 | 26.3 | iPhone 16, iOS 18.6 (the oldest 18.x installed; no 18.0 runtime on any image) |
| `macos-26` | 26.7 | 26.6 (builds the IPA) | iPhone 16, iOS 26.5 |
| `xcode-27` (public preview image) | 27.0 | 27.2 | iPhone 16, iOS 27.2 |

## Asset check

`web-dev/tools/check_assets.py` reads `web-dev/data/image_table.json` and `ui_manifest.json`, which are made from a game dump and are gitignored, so it cannot start in a checkout. `web-dev/ios/ci/check_assets_repo.py` writes stand-ins from what `web/assets` holds, runs the check unchanged and removes them. With stand-ins, pictures and interface art are compared with themselves (not a real check); voices, sounds, music, movies, fonts, interface sounds, fixed addresses in the code and the sound packs are checked for real.

Measured (2026-11-11): images 8903, voices 16460, sounds 1284, music 128, movies 45, interface art 212, sound packs 658, nothing missing. The scripts name 7,331 pictures, one of which (`26`) is not in `web/assets/img`; without the real table it cannot be told whether the game has it.
