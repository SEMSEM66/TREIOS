# TsukiREbuild for iPhone

The Tsukihime remake, *Tsukihime -A piece of blue glass moon-*, as an iPhone app. It is [TsukiREbuild](https://github.com/waifwu/TsukiREbuild), the game's engine rewritten in JavaScript and WebGL2 and playing the game's own scripts, pictures, voices, music and movies, inside a thin native shell. The app is for sideloading with a free Apple ID; it is not on the App Store. It needs iOS 18 or newer and plays in landscape, by touch.

**[⬇ Download Tsukihime-unsigned.ipa](https://github.com/SEMSEM66/TREIOS/releases/download/ios-latest/Tsukihime-unsigned.ipa)** (10 MB) · [the release it comes from](https://github.com/SEMSEM66/TREIOS/releases/tag/ios-latest)

> An unofficial, non-commercial fan project, not affiliated with TYPE-MOON or Aniplex. Please support the official release.

## Contents

- [Install it](#install-it): what you need, Sideloadly, AltStore, signing again every 7 days
- [Play it](#play-it): touch controls, saves, skipping, movies
- [When something is wrong](#when-something-is-wrong): the debug menu, the log, the compat probe
- [How far it has been tested](#how-far-it-has-been-tested)
- [The repository](#the-repository): what is where, building, tests
- [Credits](#credits)

## Install it

The download is the app alone, about 10 MB. The game's files (2.8 GB) are not inside it: the app downloads them itself the first time it is opened, over Wi-Fi, and from then on the game plays with no connection. They are kept apart from the app because a free Apple ID signs an app for 7 days, after which the app has to be signed and installed again; the files and the saves stay on the phone through that.

You need an iPhone with iOS 18 or newer and 3.5 GB of free space, a Windows PC or a Mac, a cable, and an Apple ID. A free Apple ID allows three sideloaded apps at a time.

### With Sideloadly

1. Install iTunes and iCloud **from Apple's website** (not the Microsoft Store versions) and [Sideloadly](https://sideloadly.io/).
2. Download `Tsukihime-unsigned.ipa` (the link above).
3. Connect the iPhone by cable, unlock it, and tap **Trust** if it asks.
4. Open Sideloadly, drag the IPA in, enter your Apple ID, press **Start**. It signs the app with your Apple ID and installs it.
5. On the iPhone: **Settings > General > VPN & Device Management**, tap your Apple ID, **Trust**.
6. **Settings > Privacy & Security > Developer Mode**, turn it on; the iPhone restarts and asks once more.
7. Open Tsukihime. Press **Download** and leave the app open on Wi-Fi until it finishes (it can be paused, and goes on from where it stopped). The game then starts.

### With AltStore

1. Install [AltServer](https://altstore.io/) on the PC, with iTunes and iCloud from Apple's website as above, and use it to install AltStore on the iPhone.
2. On the iPhone, download `Tsukihime-unsigned.ipa` in Safari, open AltStore, **My Apps**, **+**, and choose the IPA.
3. Trust your Apple ID and turn on Developer Mode as in steps 5 and 6 above, then open the app and download the files.

### Every 7 days

After 7 days the app stops opening until it is signed again: connect the phone and install the same IPA again with the same Apple ID. Sideloadly can do this by itself over Wi-Fi when the PC is on, and AltStore does it by itself when the iPhone and the PC running AltServer are on the same Wi-Fi. Installing over the app keeps its data.

**Do not delete the app** to "refresh" it: deleting it deletes the saves and the 2.8 GB of files. Keep to the same Apple ID and the same tool, too: a signing tool may fit the app's identifier to the Apple ID, and an app installed under another identifier starts with empty data.

## Play it

The game plays in landscape only. The picture is the game's 1920 x 1080 stage, fitted inside the screen's safe area: it stands in the middle with black beside it, clear of the Dynamic Island and of the home indicator. The page itself does not scroll, zoom or select.

| On the story | |
|---|---|
| Advance text | Tap |
| Control panel | Swipe down on the picture, or tap its top edge |
| Log | Swipe up |
| Fast forward while held | Keep a finger on the picture (everything, or only read text when Fast forward is "Read") |
| Hide text | Tap with two fingers (any tap shows it again) |
| Pass a movie | Tap (it asks first where the game does) |

The control panel is the game's quick bar at a finger's size: fifteen buttons, the game's own plates in three rows of five, each with its name under it. A tap on a plate does it and sends the panel up; a tap anywhere else, or a swipe up, only sends it up. The first time a story starts, a band across the top names the gestures until the panel has been pulled down once. iOS's own swipes from the screen's edges need a second swipe, so the game's swipes from the top and the bottom are not taken for them. The panel's FULL button has nothing to do here: the app is always full screen.

A choice takes two taps, as the game's own touch screen did: the first lights the row, a tap on the lit row takes it. Yes / No questions are drawn larger and answer at one tap.

In the menus whatever is pressed lights up, and its tap chooses it. Lists move under the finger. Back is the game's own touch Back button, which slides in at the bottom right of every screen that has a way back (on a question it is No).

- **Title.** The logo is smaller and the rows twice their size under it.
- **System menu, Save, Load.** The column's rows stand further apart. Save rows are a finger's size as they are.
- **Config.** Drawn larger across the whole width, without the column (Back returns to it). A slider follows a finger that moves along it, and a tap on its bar puts the knob there; a finger that moves up or down scrolls the page instead. Minus and plus step at a tap and repeat when held. The Controls page lists these gestures.
- **Log.** Tap a line for Quick Jump, and the speaker mark at its left to hear its voice again. Pulling on up past the newest line closes it.
- **Gallery.** In the CG viewer a tap or a swipe to the left goes to the next picture and a swipe to the right to the one before; two fingers zoom, up to four times the fitted size, and one moves a picture that has been made larger. In the flowchart a tap on a scene shows it at the right, and a tap on the scene shown opens it.

### Saves

100 save slots, a quick save, and 39 automatic saves. As in the game a save holds the latest checkpoint (a scene's start, a choice, or the first line of a page), so loading shows that page from its first line. The automatic save is made when you return to the title from the system menu, and whenever the app is left. The save screen lists all 100 slots by number, starting on the lowest empty one. The load screen lists everything there is to load, newest first: the slots in use, the quick save and the automatic saves, each named. Some chapters ask "Save Progress?"; Yes opens the save screen and the story goes on when it closes.

**Continue** on the title screen loads the save written last, so after the app has been closed, or iOS has ended it in the background, Continue takes the story up from there.

The saves are kept inside the app, and a copy of them is in the Files app under **On My iPhone > Tsukihime > Saves**; if the app ever finds its saves empty, it puts the copy back. The downloaded files are in the app's own storage and are not part of iCloud or computer backups. Both are removed when the app is deleted.

On the very first start the game opens straight on the opening movie, which asks before it can be passed ("Skip intro video?"); the title, its cautions and the story follow. After that it starts with the logos and the notice, and New Game goes straight to the story.

### Skipping and rewinding

Skipping waits at text you have not read when Fast forward is "Read" (the default) and goes on by itself at read text; on "Full" it passes everything. Choices do not turn it off; the Skip button does, and so does opening the system menu.

Rewinding (and the log's Quick Jump) goes back up to 800 points in the current session; loading a save starts the trail again. Quick load asks first, as the game does, and shows the quick save's picture.

### Movies

The 45 movies are MP4 files with AV1 video, made from the game's H.264, and the game's own AAC sound. An iPhone 16 decodes AV1 in hardware. An iPhone that has no AV1 decoder cannot play them: there the app passes each movie over and the story goes on, and no other version of the movies has been made. The compat probe (below) says which it is before anything is downloaded.

The two opening songs cannot be passed the first time they play; after that a tap asks "Skip opening animation?", in the gallery too. The end credits ask "Skip Outro?" every time. The prologue asks "Skip intro video?" on its first showing and passes without asking after that. Each question starts on No and holds the movie while it is up. The system menu does not open over a movie.

### Ciel-sensei and endings

After a bad end the game offers its "Teach Me, Ciel-Sensei!" episode: a card, then "Enter hint corner (No. n)?". Yes plays the episode and then returns to the title; No returns to the title at once. The Ending List in the gallery lists the episodes begun.

## When something is wrong

The app keeps its own log: the exact iOS version, model and chip, the page's errors, memory warnings, the download, and every time iOS ended the page. With a report of a problem, the log says most of what is needed.

- **Debug menu**: tap twice with three fingers, or shake the phone. It has the log (view, copy, share), the compat probe, the game files screen (change the source, fetch updated files, delete them) and a reload.
- **Files app**: **On My iPhone > Tsukihime > Logs** holds `debug.log`, the one before it, and `probe-result.json`.
- **Compat probe**: measures what this iPhone does with everything the game needs (pictures, sound, AV1 movies, storage, fonts). The download screen has a button for it, so it runs before any files are downloaded, and **Share the results** sends them anywhere the share sheet reaches.

## How far it has been tested

- **In simulators, on every push.** GitHub Actions builds the app and runs it in iPhone 16 simulators on iOS 18.6, 26.5 and 27.2: the compat probe, the story from its start, the automatic save on a memory warning, the recovery when iOS ends the page or takes its graphics context away, a scene that opens with a movie, and a download from the release that is cut short and taken up again.
- **On an iPhone 16 with iOS 18.7.8.** One session of half an hour: the download (18 minutes on Wi-Fi), the AV1 movies, voices, music and sound effects (also with the ring/silent switch on silent), touch, the menus, saving, and the story taken up again after the app was closed. The story ran at 57.5 to 60 frames a second.
- **Not tried on a phone yet:** a movie watched to its end, leaving the app and coming back without closing it, a session of 30 minutes or more, signing again after 7 days, the Files app, the debug menu's gestures, and any iPhone other than the 16.

[NOTES.md](web-dev/ios/NOTES.md) has the measurements and the full list of what is unverified.

## The repository

| Path | What is in it |
|---|---|
| `web-dev/ios/` | The iPhone app: the Swift sources (`App/Sources`), the page's bridge and the compat probe (`App/Web`), `build_ipa.sh`, and CI's scripts (`ci/`). [README.md](web-dev/ios/README.md) there is about building it, the asset packs, how it works and the checklist for a real iPhone; [NOTES.md](web-dev/ios/NOTES.md) holds the measurements and decisions. |
| `web/` | The game, as upstream makes it: `app/` (engine, interface, styles, fonts), `assets/` (the game's converted files, 2.7 GB) and `server.py`, which serves it to a desktop browser for development. |
| `web-dev/tests/` | The engine's tests. |
| `web-dev/tools/` | `build_ios_packs.py` cuts `web/assets` into the packs the app downloads. `check_assets.py`, with `needed.py` and `build_packs.py`, says whether `web/assets` is complete. `build_animations.py` is upstream's exporter of the motion tracks, kept because a test reads it. |
| `.github/workflows/ios.yml` | Tests, builds and publishes all of it. |

GitHub Actions builds the app, with no Mac and no signing. A push to the `ios` branch runs the engine tests and the asset check, cuts the asset packs, builds the app and runs it in the simulators, and leaves the unsigned IPA and the packs on the release [`ios-latest`](https://github.com/SEMSEM66/TREIOS/releases/tag/ios-latest).

The tests need Node.js and no packages: `node --test web-dev/tests/*.test.mjs`. The asset check: `python3 web-dev/ios/ci/check_assets_repo.py`.

`web/app` is upstream's engine with two small additions for the app: its address in `home.js`, so that it opens on the game, and `?resume` in `main.js`, which goes straight to the newest save. It is otherwise unchanged, so it still carries the website's opening page, which the app never shows.

What is not here is upstream's, at [waifwu/TsukiREbuild](https://github.com/waifwu/TsukiREbuild): the website, the Android app and the Windows, macOS and Linux app, the tools that convert a game dump into `web/assets`, the parity audit and the research behind the port. The tests' comments that name `web-dev/audit` mean the one there.

## Credits

- **The port.** The engine, the conversion of the game's files, the tests, the Android and desktop apps and the website [arcueid.date](https://arcueid.date/) are the work of [waifwu/TsukiREbuild](https://github.com/waifwu/TsukiREbuild). This repository began as a copy of it and keeps what the iPhone app needs: everything in `web/` and `web-dev/tests/` is upstream's. What it adds is the iPhone app in `web-dev/ios/`.
- **The game.** The Tsukihime remake, *Tsukihime -A piece of blue glass moon-*, and all of its story, art, music and voices belong to TYPE-MOON, Aniplex and the other rights holders. This project is unofficial and non-commercial, and is not affiliated with or endorsed by them. Please support the official release.
- **English text.** The English script comes from the Tsukihimates fan translation patch.
- **Built on.** The native port this grew from is based on the SuperMarioWonderRecomp recompilation framework by BelmanteGu. Ryujinx's shader translator was used offline; Ghidra for decompilation; FFmpeg, SVT-AV1 and Pillow for the conversions.
- **Fonts.** Inter, Gelasio, Arimo and PT Sans Narrow under the SIL Open Font License; Ubuntu and Ubuntu Condensed under the Ubuntu Font Licence; TeX Gyre Chorus and Pagella under the GUST Font License. Each licence is beside its font in `web/app/fonts/`.
- **How it was written.** Built with Claude, Anthropic's AI model, under human direction: the goals, the decisions and the playing and judging of every result were human, and most of the code was written by the AI.
