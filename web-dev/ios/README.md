# iPhone app

The web port as an iPhone app: a thin native shell around `web/app`, the way the Android app is. It is built for sideloading with a free Apple ID; it is not for the App Store. iOS 18 or newer, iPhone only, landscape.

Unlike the Android APK, the IPA does not carry the game's files. At 2.7 GB they are over what a GitHub release holds in one file, and a sideloaded app is signed and installed again every 7 days. The IPA is about 10 MB; on its first launch the app downloads the files once (2.8 GB, Wi-Fi), and from then on the game plays with no connection.

GitHub Actions builds everything, with no Mac and no signing: every push to the `ios` branch leaves, on the release [`ios-latest`](../../../../releases/tag/ios-latest):

- `Tsukihime-unsigned.ipa`, the app;
- `index.json` and the `assets-*.part` files, the asset packs the app downloads.

## Installing it without a Mac

You need a Windows PC (or a Mac), a cable, and an Apple ID. A free Apple ID signs an app for 7 days and allows three sideloaded apps at a time; after 7 days the app stops opening until it is signed again (below). The saves and the downloaded files stay through that.

### Sideloadly

1. Install iTunes and iCloud **from Apple's website** (not the Microsoft Store versions) and [Sideloadly](https://sideloadly.io/).
2. Download `Tsukihime-unsigned.ipa` from the release.
3. Connect the iPhone by cable, unlock it, and tap **Trust** if it asks.
4. Open Sideloadly, drag the IPA in, enter your Apple ID, press **Start**. It signs the app with your Apple ID and installs it.
5. On the iPhone: **Settings > General > VPN & Device Management**, tap your Apple ID, **Trust**.
6. On iOS 16 or newer: **Settings > Privacy & Security > Developer Mode**, turn it on; the iPhone restarts and asks once more.
7. Open Tsukihime. Press **Download** and leave the app open on Wi-Fi until it finishes (it can be paused; it goes on from where it stopped). The game then starts.

Every 7 days: connect the phone and install the same IPA again with the same Apple ID (Sideloadly can also do this by itself over Wi-Fi when the PC is on). Installing over the app keeps its data. **Do not delete the app** to "refresh" it: deleting it deletes the saves and the 2.8 GB of files.

### AltStore

1. Install [AltServer](https://altstore.io/) on the PC, with iTunes and iCloud from Apple's website as above, and use it to install AltStore on the iPhone.
2. On the iPhone, download `Tsukihime-unsigned.ipa` (Safari, from the release), open AltStore, **My Apps**, **+**, and choose the IPA.
3. Trust your Apple ID and turn on Developer Mode as in steps 5 and 6 above, then open the app and download the files.

AltStore signs the app again by itself when the iPhone and the PC running AltServer are on the same Wi-Fi; open AltStore now and then to check the days left.

Both tools put your Apple ID's team into the app's bundle ID. Keep using the same Apple ID and the same tool, and updates and re-signing keep the saves and the files; a different Apple ID installs it as another app with empty data.

## Playing

- Touch controls are the web version's (the first-launch hints show them). The system's own edge swipes need a second swipe, so the game's swipes from the top and the bottom are not taken for them.
- Leaving the app makes the automatic save, as on Android. If iOS ends the app in the background, **Continue** on the title screen takes the story up from there.
- The saves are the page's `localStorage`, and a copy of them is kept in the Files app under **On My iPhone > Tsukihime > Saves**. If the page's storage is ever found empty, the copy is put back.
- The downloaded files are in the app's own storage, are not part of iCloud or computer backups, and are removed only when the app is deleted (or from the debug menu).

## When something is wrong

There is no Safari Web Inspector without a Mac, so the app keeps its own log: the exact iOS version, model and chip, the page's console and errors, memory warnings, the download, and every time iOS ended the page.

- **Debug menu**: tap twice with three fingers, or shake the phone. It has the log (view, copy, share), the compat probe, the game files screen (change the source, fetch updated files, delete them) and a reload.
- **Files app**: On My iPhone > Tsukihime > Logs holds `debug.log`, the one before it, and `probe-result.json`.
- **Compat probe**: measures what this iPhone's WebKit does with everything the game needs (WebGL2, AVIF and WebP, Ogg Opus, AV1, H.264 and HEVC movies, sound without a tap, storage, fonts, the app's file serving). The download screen has a button for it, so it runs before any files are downloaded. **Share the results** sends the files anywhere the share sheet reaches.

## Building it

```bash
web-dev/ios/make_probe_media.sh        # the probe's test clips (needs ffmpeg); optional
web-dev/ios/build_ipa.sh               # build/Tsukihime-unsigned.ipa
web-dev/ios/build_ipa.sh --sim         # build/Tsukihime-sim.app, for the iOS Simulator
python3 web-dev/tools/build_ios_packs.py   # build/packs: index.json and the parts
```

`build_ipa.sh` needs a Mac with Xcode and XcodeGen (`brew install xcodegen`); the Xcode project is generated from `project.yml` and is not in the repository. It signs nothing. `--asset-url` sets where the app looks for the packs (the folder that holds `index.json`); CI sets it to this repository's `ios-latest` release. `--no-debug-ui` leaves the debug menu out.

`.github/workflows/ios.yml` is the same thing on GitHub's runners: the engine tests and the asset check on Linux, the packs and the probe's clips on Linux, then the app on macOS, where it is also run in an iPhone 16 simulator (the compat probe, the game, a memory warning and an ended page, a download from the release cut short and taken up again). Screenshots, videos and logs of those runs are the workflow's artifacts.

## The asset packs

`build_ios_packs.py` cuts `web/assets` (without the loose voices and sound effects, which the sound packs carry, as in the Android app) into parts of at most 96 MiB. A part is its files one after another, uncompressed; `index.json` lists every part with its size and SHA-256 and the files in it with their sizes. A part is named after its hash, and each folder of `web/assets` starts a new part, so a build that changes one folder uploads, and a phone downloads, only that folder's parts.

The app fetches `index.json`, then each part it does not have: downloaded to a temporary file (an interrupted part goes on with an HTTP `Range`), checked against its SHA-256, written out as files, deleted. It needs the size of the game plus one part of free space. To host the packs somewhere else, put `index.json` and the parts in one folder of any web server that answers `Range` requests and set that folder's address under **Source** on the download screen (plain `http` works for an address on your own network).

## How it works

- `GameViewController.swift` opens a `WKWebView` at `app://tsukihime.ios/`, a name that never reaches the network, as the desktop app does with `app://tsukihime.desktop/`. `SchemeHandler.swift` answers every request to it from files: `web/app` from the app bundle, `/assets/...` from the downloaded files, with byte ranges (206) for the movies. Any other address is refused; a link the player taps opens in Safari.
- `web/app` is used as it is. `home.js` knows the app's address, so the app opens on the game and not on the site's opening page. `bridge.js` is added to the page by the app and is not part of `web/app`: it sends the console to the log, mirrors `localStorage` to a file, and passes a movie that neither plays nor fails.
- Landscape only, no status bar, the home indicator hidden or dimmed, the screen kept on. Movies play inline and sound needs no first tap. The audio session is `playback`, so the ring/silent switch does not mute the game.
- Going to the background calls `appSuspend()` in `main.js`, as the Android app does. A memory warning calls it too. If iOS ends the page's process, the app loads the page again with `?resume`, which goes straight to the newest save.

`NOTES.md` has the measurements behind these choices, the compatibility matrix, and what is still unverified on a real iPhone.
