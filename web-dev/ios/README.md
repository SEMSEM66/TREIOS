# The iPhone app: building it and how it works

How to install and play the app is in the [main README](../../README.md). This page is about trying it on a real iPhone, building it, the asset packs, and how it works.

The app is a thin native shell around `web/app`, upstream's engine. It is built for sideloading with a free Apple ID; it is not for the App Store. iOS 18 or newer, iPhone only, landscape.

The IPA does not carry the game's files. At 2.7 GB they are over what a GitHub release holds in one file, and a sideloaded app is signed and installed again every 7 days. The IPA is about 10 MB; on its first launch the app downloads the files once (2.8 GB, Wi-Fi), and from then on the game plays with no connection.

GitHub Actions builds everything, with no Mac and no signing: every push to the `ios` branch leaves, on the release [`ios-latest`](../../../../releases/tag/ios-latest):

- `Tsukihime-unsigned.ipa`, the app;
- `index.json` and the `assets-*.part` files, the asset packs the app downloads.

## Checking it on an iPhone

CI runs the app in simulators, which cannot show how a real phone decodes the movies, how fast it draws, or what it does under memory pressure (`NOTES.md` lists what is unverified). A first pass on an iPhone 16 with iOS 18.7.8 went well: the download, the AV1 movies, the sound, touch and the saves all work there, and `NOTES.md` ("On the iPhone 16") has what it showed and what is left. This is the list to go through on the phone; after it, share the debug log (step 12), which records most of the answers by itself.

1. **Install** the IPA (the main README has the steps). Note whether Sideloadly or AltStore complained about anything.
2. **Compat probe, before downloading**: on the download screen tap **Compat probe**. Wait for the summary line, tap **Play a test tone** once with the ring/silent switch on silent (is it heard?), then **Share the results**. The summary says whether AV1 and Ogg Opus work on this phone.
3. **First-run download**: back on the download screen, **Download** on Wi-Fi. Try **Pause** and **Resume** once, and leave the app and come back once. Note the time it took and whether it finished by itself.
4. **Opening movie**: start a new game and let the opening play. Does it play, smoothly, with sound in step with the picture? (If the phone cannot decode it, the game goes on without it and the log says so.)
5. **A scene with voice, music and sound effects**: play a few minutes. Is anything silent, late or crackling? Try the ring/silent switch.
6. **Choices**: reach a choice and pick one by touch.
7. **Save and load**: save to a slot, load it, and try the quick save.
8. **Background, then resume**: go to the Home Screen for a minute and come back. The story and the music should go on.
9. **Kill, then Continue**: swipe the app away in the app switcher, open it again, and choose Continue on the title screen. It should be where you left.
10. **Airplane mode**: turn it on, open the app, play a few minutes with a movie or two. Nothing should be missing.
11. **A 30-minute session**: play on. Note any stutter, heat, a reload in the middle of play, or the app closing.
12. **Share the debug log**: tap twice with three fingers (or shake the phone), **Share debug log**, and send the files. If the gesture does not open the menu, the same files are in the Files app under On My iPhone > Tsukihime > Logs.

Also worth a look: the picture's margins beside the Dynamic Island and above the home indicator, and whether the game's swipes from the top and bottom edges work without the system taking them.

## Building it

```bash
web-dev/ios/make_probe_media.sh        # the probe's test clips (needs ffmpeg); optional
web-dev/ios/build_ipa.sh               # build/Tsukihime-unsigned.ipa
web-dev/ios/build_ipa.sh --sim         # build/Tsukihime-sim.app, for the iOS Simulator
python3 web-dev/tools/build_ios_packs.py   # build/packs: index.json and the parts
```

`build_ipa.sh` needs a Mac with Xcode and XcodeGen (`brew install xcodegen`); the Xcode project is generated from `project.yml` and is not in the repository. It signs nothing. `--asset-url` sets where the app looks for the packs (the folder that holds `index.json`); CI sets it to this repository's `ios-latest` release. `--no-debug-ui` leaves the debug menu out.

`.github/workflows/ios.yml` is the same thing on GitHub's runners: the engine tests and the asset check on Linux, the packs and the probe's clips on Linux, then the app on macOS, where it is also run in iPhone 16 simulators on iOS 18, 26 and 27: the compat probe, the game, a memory warning and an ended page, a scene that opens with a movie, and a download from the release that is cut short and taken up again. `ci/check_run.py` checks what each run left and fails the job if something that must hold does not. The app's own pictures of the game, the logs and the probe's results are the workflow's artifacts.

## The asset packs

`build_ios_packs.py` cuts `web/assets` (without the loose voices and sound effects, which the sound packs carry, as in upstream's Android app) into parts of at most 96 MiB. A part is its files one after another, uncompressed; `index.json` lists every part with its size and SHA-256 and the files in it with their sizes. A part is named after its hash, and each folder of `web/assets` starts a new part, so a build that changes one folder uploads, and a phone downloads, only that folder's parts.

The app fetches `index.json`, then each part it does not have: downloaded to a temporary file (an interrupted part goes on with an HTTP `Range`), checked against its SHA-256, written out as files, deleted. It needs the size of the game plus one part of free space. To host the packs somewhere else, put `index.json` and the parts in one folder of any web server that answers `Range` requests and set that folder's address under **Source** on the download screen (plain `http` works for an address on your own network).

## How it works

- `GameViewController.swift` opens a `WKWebView` at `app://tsukihime.ios/`, a name that never reaches the network, as upstream's desktop app does with `app://tsukihime.desktop/`. `SchemeHandler.swift` answers every request to it from files: `web/app` from the app bundle, `/assets/...` from the downloaded files, with byte ranges (206) for the movies. Any other address is refused; a link the player taps opens in Safari.
- `web/app` is used as it is. `home.js` knows the app's address, so the app opens on the game and not on the site's opening page. `bridge.js` is added to the page by the app and is not part of `web/app`: it sends the console to the log, mirrors `localStorage` to a file, and passes a movie that neither plays nor fails.
- Landscape only, no status bar, the home indicator hidden or dimmed, the screen kept on. Movies play inline and sound needs no first tap. The audio session is `playback`, so the ring/silent switch does not mute the game.
- Going to the background calls `appSuspend()` in `main.js`, as upstream's Android app does. A memory warning calls it too. If iOS ends the page's process, the app loads the page again with `?resume`, which goes straight to the newest save.

`NOTES.md` has the measurements behind these choices, the compatibility matrix, and what is still unverified on a real iPhone.
