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

## What CI runs, and what it showed

Every push to `ios` runs `.github/workflows/ios.yml`: the engine tests and the asset check on Linux; the packs and the probe's test clips on Linux; then the app on macOS, built for the simulator and as the unsigned IPA, and run in an iPhone 16 simulator. Each simulator run is checked by `ci/check_run.py`, which fails the job when something that must hold does not; the table it prints is the job's summary.

A runner has no graphics card and 7 GB of memory. While the game draws, the Mac itself barely answers: `simctl io screenshot` times out, a step's own time limit is not enforced, and a cancelled job loses its log (all three seen in the first runs). So the game is the last thing each run does, the app takes its own pictures (`-TsukiSnapshotEvery`) and quits by itself (`-TsukiQuitAfter`), and what a run found is uploaded before the game starts and again after it. Frame rates in the simulator were 7 to 53 a second and say nothing about a phone.

Two runs per simulator version, each on a runner of its own:

- **checkout**: the compat probe; then the game with `web/assets` read from the checkout, with a memory warning once the story is under way and the page's process ended 8 s later; then the game again at a scene that opens with a movie (`01_00_ARC01_1`).
- **download**: a fresh install fetches the packs from the release and quits in the middle of part 12; the second launch goes on from there; then the game from the downloaded files.

Measured in runs 43146749390 and 43149336042 (2026-11-12):

| Check | iOS 18.6 | iOS 26.5 | iOS 27.2 |
| --- | --- | --- | --- |
| The page loads from `app://tsukihime.ios/`, secure context, touch-first | yes | yes | yes |
| The safe area reaches the page (left 59, bottom 20 or 21, right 59) | yes; once it arrived after `load` (see risk 9) | yes | yes |
| The story runs: the script moves on, the app's pictures show the art and the text | yes | yes | yes |
| Errors from the page, other than movies that cannot be decoded | none | none | none |
| A memory warning makes the automatic save (`appSuspend`) | yes | yes | yes |
| The page's process is ended: noticed, reloaded with `?resume`, the story goes on in the same scene | yes | yes | yes |
| The saves reach `Documents/Saves/localStorage.json` | yes | yes | yes |
| A scene's movie cannot be decoded (no AV1 in a simulator): the story goes on by itself | yes | yes | yes |
| The title screen without its movie: the menu is drawn over the title's own art | not looked at | yes | not looked at |
| Download from the release, cut in the middle of a part, taken up with `Range`, every checksum right | yes | yes | not run |
| The assets folder is excluded from backup | yes | yes | not run |

The iOS 27 runner image is a public preview: its newest runtime is for one model only and refused an iPhone 16 ("Incompatible device"), so the boot step falls back to the image's next iOS 27 runtime, which took one. A failure on that image does not fail the run.

## Compatibility matrix

From the compat probe (`App/Web/probe.js`), which runs in the app and is served like the game. The simulator columns are measured; the iPhone 16 column waits for a device report.

| What the game needs | iOS 18.6 sim | iOS 26.5 sim | iOS 27.2 sim | iPhone 16 |
| --- | --- | --- | --- | --- |
| WebGL2 context as `renderer.js` opens it; a shader draws and reads back | yes | yes | yes | **needs device** |
| AVIF through `createImageBitmap` with the engine's options, uploaded as a texture (a 1219x4238 standing picture of the game) | yes, 80 ms | yes, 144 ms | yes, 96 ms | **needs device** |
| WebP (interface art) | yes | yes | yes | **needs device** |
| Ogg Opus through `decodeAudioData` (made by CI, and a sound of the game) | yes | yes | yes | **needs device** |
| The audio context runs with no tap | yes | yes | yes | **needs device** |
| AV1 movie (made by CI, and the game's logo movie) | no | no | no | **needs device**: the only way to know |
| H.264 movie through the app's file serving, with a seek | yes | yes | yes | **needs device** |
| HEVC movie | yes | yes | not read | **needs device** |
| `localStorage` room beside the saves | 4.75 M characters | 4.75 M characters | 4.75 M characters | **needs device** |
| Byte ranges from the scheme handler (206, the right bytes; open-ended and suffix ranges) | yes | yes | yes | same code |
| A bundled web font | yes | yes | not read | **needs device** |
| Fullscreen API, `screen.orientation.lock`, `keyboard.lock` | absent | absent | not read | expected absent |

Why AV1 fails in every simulator: there is no AV1 decoder there (`VTIsHardwareDecodeSupported` is false for all three codecs on a runner, and WebKit on iOS has no software AV1 decoder). It says nothing about the A18.

Other things the probe measured:

- `canPlayType('video/mp4; codecs="av01.0.08M.08"')` answers "probably" where AV1 cannot be played. `mediaCapabilities.decodingInfo` answers "supported false" there, so that is what the app asks.
- Sound formats a fallback could use, should one ever be needed: Opus in WebM and in CAF, AAC in M4A and MP3 all decode through `decodeAudioData`; Opus in MP4 does not.
- A movie's `volume` could be set in the simulator (it read back 0.05). On iPhones a page has historically not been able to set it; the game sets a movie's volume from the music volume. **needs device.**
- The Fullscreen API and orientation lock are absent in WKWebView on an iPhone. Every use of them in the engine is an optional call, and no run logged an error from the page.

## Findings and decisions, by risk

1. **Movies.** All 45 are AV1 (Main, 8 bit, 4:2:0, 1080p, AAC sound). No fallback has been built, as agreed: it waits for the iPhone 16's probe. What is in place: the app asks WebKit whether AV1 plays and, where it does not, serves `assets/movie-h264/NAME.mp4` or `assets/movie-hevc/NAME.mp4` in place of `assets/movie/NAME.mp4` if such a file is installed, so a fallback pack would need no change to the engine. With no fallback installed a movie that cannot play is passed: the engine does that itself when the movie reports an error or `play()` is refused (measured for the prologue movie, a phase title, the logo and the title's movie), `bridge.js` logs it, and a movie that neither plays nor fails for 8 seconds is given the error it should have had (that last path has not been seen to fire). H.264 and HEVC both decode in the simulators. If a fallback is needed it would be a manually started workflow that transcodes the repository's AV1 files with ffmpeg, copies the AAC stream, keeps each file's frame rate and timestamps, and publishes the result as one more pack.
2. **Sound.** Ogg Opus decodes on iOS 18.6, 26.5 and 27.2 (simulators, which decode in software as a phone does). iOS 18.0 to 18.5 could not be measured: no runner has those runtimes. The app decodes a small Ogg Opus file as the game starts and, if that fails, says so on screen and in the log rather than playing silently. No WASM decoder and no second set of sound packs have been built. If a device needs one, the probe's rows say Opus in CAF would decode, which is a change of container with no re-encoding of the sound.
3. **AVIF.** Decodes on all three, the engine's exact call included.
4. **File serving.** `WKURLSchemeHandler` works for everything, movies with seeking included. No loopback server. The origin is a secure context.
5. **Media policy.** Inline playback and no-tap playback are set and measured. The audio session is `.playback` natively, and `navigator.audioSession.type` is set to "playback" in the page. Whether the ring/silent switch leaves the sound on, and what a call or an alarm does, **needs device**: the probe has a "Play a test tone" button for the switch, and interruptions and route changes are logged.
6. **Memory.** Memory warnings are logged and make the automatic save. A page process that iOS ends is reloaded straight to the newest save, at most three times a minute (measured by ending the process on purpose; the debug menu has the same test). In debug builds the log has frames a second and the longest frame once a minute. Whether `preload.js` reading ahead is too much for a phone's page process is **needs device**; no lower-memory profile has been built, because nothing has shown one is needed. One number to watch: music is decoded whole, about 84 MB of samples for a 218 s track.
7. **Saves.** Every change to a `tsuki.*` key of `localStorage` is mirrored to `Documents/Saves/localStorage.json` (measured: the file is written, and holds the automatic save). A page that starts with no `tsuki.*` keys takes the mirror back; that restore has not been exercised in CI.
8. **Desktop-browser assumptions.** The page is touch-first by the engine's own media query. The opening page is skipped by host name, as in the other apps.
9. **Layout and gestures.** Landscape is locked by Info.plist and the view controllers; the web view is edge to edge with `contentInsetAdjustmentBehavior = .never`; the page reads the safe area. One real fault found by CI: the insets do not always reach the page with it. On iOS 18.6 they once arrived after `load` with no change of window size, and the engine fits its stage only when the window changes; on iOS 26.5 they once never arrived at all (the view had 59 points at each end, `env()` read 0 for the whole run), which leaves the stage under the Dynamic Island. So the app now tells the page its view's own insets; where `env()` reads nothing and the app has some, `bridge.js` gives them to the engine's probe element, and whenever the insets in force change it sends the page a `resize` (measured for the late arrival: 0 0 0 0, then 0 59 21 59, and the stage in the app's pictures sits inside them; the never-arriving case is covered by the same check in CI but only shows when WebKit misbehaves again). Status bar hidden, home indicator auto-hidden, edge gestures deferred on all edges, no back/forward swipe, idle timer off: all set, none of them visible to CI. **needs device.**

## Needs device

None of this can be shown by a simulator. The checklist is in README.md ("Checking it on an iPhone").

- The exact iOS version, model and chip (the log's first lines and the probe record them).
- AV1: whether the A18 decodes the game's movies, smoothly, with sound in step. Decides whether a fallback is built.
- Ogg Opus on the phone's iOS version, if it is older than 18.6.
- Frame rate and heat over a long session; memory warnings and ended page processes (all in the log).
- The ring/silent switch, calls, alarms, headphones being pulled out.
- A movie's volume following the music volume.
- The margins beside the Dynamic Island and above the home indicator as they look, the home indicator's visibility, edge swipes, the three-finger double tap and the shake that open the debug menu.
- Touch itself: CI drives the game with key events, so no tap, swipe or pinch has been tried on WebKit.
- The download on real Wi-Fi: pausing, leaving the app, the screen staying on, no mobile data used.
- Signing: that Sideloadly and AltStore accept the unsigned IPA, and that re-signing after 7 days with the same Apple ID keeps the saves and the files.
- The Files app showing Logs and Saves; sharing the log.
