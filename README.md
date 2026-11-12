# TsukiREbuild

The Tsukihime remake, *Tsukihime -A piece of blue glass moon-*, rebuilt to play in a web browser, on Android, and as an app on Windows, macOS and Linux. The game's engine was rewritten in JavaScript and WebGL2, and that new engine plays the game's own scripts, pictures, voices, music and movies. Wherever the port had to decide how something looks, sounds or moves, the answer was taken from the game itself and checked against it frame by frame.

**[▶ Play online](https://arcueid.date/)** · ⬇ Download: **[Windows](https://arcueid.date/desktop/Tsukihime-win-x64.zip)** (2.9 GB) · **[Android](https://arcueid.date/android/tsukihime.apk)** (2.8 GB) · macOS and Linux: [build it](#on-windows-macos-and-linux)

> An unofficial, non-commercial fan project, not affiliated with TYPE-MOON or Aniplex. Please support the official release.

## Contents

- [Play it](#play-it): in a browser, on Android, on an iPhone, on Windows, macOS and Linux, from this folder
- [Controls](#controls): mouse and keyboard, touch, controller
- [How it plays](#how-it-plays): the opening page, saves, skipping, movies, Ciel-sensei
- [Under the hood](#under-the-hood): loading, fonts, opening a particular scene
- [The repository](#the-repository): what is where, making the assets again, tests
- [Credits](#credits)

## Play it

### In a browser

Open **[arcueid.date](https://arcueid.date/)** in Chrome or Firefox, on a computer, a phone or a tablet. Nothing is installed: the game's files arrive as you play, and saves stay in the browser.

The site opens on a page with four tabs: **ABOUT** (what this is and how it was made), **GITHUB**, **DOWNLOAD** (the apps below), and **PLAY ONLINE**, whose PRESS ANY BUTTON starts the game.

**It does not work in Safari.** The movies are AV1 video, which Safari plays only on Apple's newest hardware (it has no decoder of its own), and the game has not been tried there.

### On Android

**[Download Tsukihime.apk](https://arcueid.date/android/tsukihime.apk)** (2.8 GB). It is the whole game in one app: every picture, voice, song and movie is inside it, so it needs no connection, and it asks for no permissions at all.

1. Download it on the phone itself. It is large, so Wi-Fi is best.
2. Open it from the browser's downloads. Android asks whether that browser may install apps: allow it.
3. Install. As much space again must be free while it installs; afterwards the download can be deleted.

It needs Android 8 or newer and plays in landscape, by touch, as the site does on a phone. Android's Back gesture does what the game's own Back button does, and leaving the app makes the automatic save. Saves are kept in the app, apart from the website's, and a newer APK installs over the old one with them kept. How it is built: [web-dev/android/README.md](web-dev/android/README.md).

### On an iPhone

There is an iPhone app too, for sideloading with a free Apple ID (Sideloadly or AltStore); it is not on the App Store. It is the same game in a thin native shell, for iOS 18 or newer. The app itself is about 10 MB: on its first launch it downloads the game's files once (2.8 GB, over Wi-Fi), and then plays with no connection. GitHub Actions builds it, unsigned, with no Mac needed. How to install it, what a free Apple ID means (the app is signed again every 7 days; the saves and the files stay), and how it is built: [web-dev/ios/README.md](web-dev/ios/README.md).

### On Windows, macOS and Linux

The whole game as a desktop app, with every picture, voice, song and movie inside it and no connection needed. It is the same web port in a window of its own (Electron), opening on the game itself. Closing the window makes the automatic save. Saves are kept in the app's own data folder, apart from the website's, and stay when a newer version replaces the app.

**Windows** (10 or newer, 64-bit): **[download Tsukihime-win-x64.zip](https://arcueid.date/desktop/Tsukihime-win-x64.zip)** (2.9 GB).

1. Right-click the file and choose Extract All, into a folder of its own. There is nothing to install.
2. Open `Tsukihime.exe` in that folder. Windows may say it does not know the publisher: More info, then Run anyway.

**macOS and Linux** have no download yet (the site's storage has no room for them). The app is the same one, and one command builds it from this repository, which carries the game's files:

```bash
git clone --depth 1 https://github.com/waifwu/TsukiREbuild
cd TsukiREbuild
web-dev/desktop/build.sh mac      # on a Mac: web-dev/desktop/out/Tsukihime-mac-universal.dmg
web-dev/desktop/build.sh linux    # web-dev/desktop/out/Tsukihime-linux-x86_64.AppImage
```

It needs Git, Node.js with npm, and about 20 GB free while it builds; the first run fetches Electron. The Mac app is for macOS 13 or newer, Apple silicon and Intel: open the `.dmg` and drag Tsukihime to Applications. The Linux one is for 64-bit (x86) systems: `chmod +x` it and open it (it needs FUSE, `libfuse2`; without it, add `--appimage-extract-and-run`). How it works: [web-dev/desktop/README.md](web-dev/desktop/README.md).

### On your own computer

```bash
python3 web/server.py 8765
```

Then open http://localhost:8765. It needs Python 3, with no packages, and the `web` folder: everything the game uses is in `web/assets/` (2.7 GB). Nothing else in the repository is read, nor the game's own files, so that folder can be moved by itself. The browser needs WebGL2, AVIF, Opus and AV1 video; Chrome and Firefox have them all.

## Controls

### Mouse and keyboard

The interface is made for a mouse and a keyboard. The story itself (pictures, text, sound, movies) plays as the game plays it; the screens around it keep the game's art and follow one rule:

- **The mouse.** What is under the pointer lights up, one click chooses it, a right click goes back, and the wheel scrolls. On the story screen a click advances, a right click opens the system menu, the wheel up opens the log and down advances, and a middle click hides the text (any click shows it again). The pointer goes out of sight when it rests over the story. A click draws the game's touch ring. There is no Back button on the screens: a right click (or Esc) is Back everywhere, and a button's caption shows only while the pointer is on it.
- **The quick bar.** Move the mouse to the top of the picture. It is the game's own bar and buttons (previous scene, previous message, auto, skip, next scene, Q.SAVE, Q.LOAD, voice) with LOG, HIDE, SAVE, LOAD, CONFIG, FULL and MENU after them, cut from the same art. Pointing at a button shows what it does and its key. Any click sends the bar up again. The two scene buttons and Q.LOAD ask first, starting on No.
- **The keys.** One map for every screen, shown on the config's Controls page, where a click on a key (or Enter) and then the new key changes it; Esc cancels, Backspace clears, and "Reset to defaults" puts them back.

| Action | Default key |
|---|---|
| Advance text | Enter, Space |
| Fast forward while held | Ctrl (everything, or only read text when Fast forward is "Read") |
| Skip read text on / off | S |
| Auto mode on / off | A |
| Log | L, Page Up |
| Previous message | R |
| Hide text | H |
| Replay voice | V |
| Quick save, quick load | Q, W |
| Return to previous scene, jump to next scene | P, N |
| Quick bar by keys | Up (then Left / Right, Enter; Esc closes) |
| System menu | Esc |
| Full screen | F |
| Save, Load, Config | none until you give them one |

The game goes full screen when it is started from PLAY ONLINE, and after that at any click, until F (or the quick bar's FULL) takes it out; F again puts it back. Esc still opens the menu in full screen, where the browser allows it.

In every menu the arrows move, Enter or Space chooses, Esc or Backspace goes back, Tab changes the config's page (Shift + Tab the other way), Page Up / Page Down scroll, and Home / End go to the first / last. The bar along the bottom of each screen says what is there.

- **Choices** start with nothing selected: the pointer lights a row and a click takes it; Up / Down or the wheel pick a row (Left / Right the first or last) and Enter takes it. Rows the story has not opened yet are shown but cannot be picked. The story's own yes / no questions also start on neither: point and click, or Up for No and Down for Yes.
- **The log** shows every page so far, the one on screen too, one under another as the text window drew them, opened at the newest. The wheel, the scroll bar and Page Up / Page Down scroll it, and scrolling on past the end closes it. A click on a line (or Up / Down and Enter) asks "Quick Jump?" (starting on No) and goes back to that line; a line with a voice has a speaker mark at its left, and a click on it (or V on the cursor's line) plays the voice again.
- **The config.** Its System page has its words at one size, 28 px, on every device: the translated art had the rows' names, the choices, the toggles and the samples at five different sizes, so the three pictures that carry them are drawn again as the game starts (`app/js/confart.js`). A click on a slider's bar puts the knob there, and it can be dragged; minus and plus step 1 (50 for the auto mode waits) and repeat when held; holding Enter on a slider, Left / Right step it; the wheel or a drag scrolls the page.
- **The gallery.** In the CG viewer a click or Left / Right change the picture, Enter toggles fill and fit, Up / Down, + / - or the wheel zoom, dragging moves the picture and Home resets it. In the Music Player a click on the position bar moves the track there.

The chapter in the system menu's header, on each save row and down the flowchart's left side is written out as text, one line each, in the look of the game's pictures of them (the translated pictures had to break long names over two small lines to fit the game's cells). The system menu's header (and Save, Load and Config under it) names the music playing: "Audio Track", and under it a turning disc and the title. From the title the gallery opens on the game's own one-second fade, without the 0.35 s stop the game makes after it.

### Touch: phones and tablets

A device played by touch gets a touch interface: one whose first pointer is a finger that cannot hover (`(hover: none) and (pointer: coarse)`), which means phones and tablets. A laptop with a touch screen, a narrow desktop window and a tablet with a mouse attached keep the mouse and keyboard interface, which is unchanged. `?touch=1` in the address forces the touch interface and `?touch=0` the other; it is decided once, as the page loads.

**The opening page** works held either way: held upright it has a layout of its own, its four plates in two rows over a taller column. **The game plays in landscape.** Once PLAY ONLINE has started it, a phone held upright shows a screen asking for it to be turned, and everything is held under it (the story's clocks, sound, movies, the screens' own motion) until it is. The picture is the game's 1920 x 1080 stage, fitted inside the screen's safe area: on a phone wider than 16:9 it stands in the middle with black beside it, clear of a notch and of the home bar. The game goes full screen when it is started, and where the browser lets a page do so, landscape is locked there. The page itself does not scroll, zoom or select: pull to refresh, double-tap and pinch zoom and the long-press menu are off.

| On the story | |
|---|---|
| Advance text | Tap |
| Control panel | Swipe down on the picture, or tap its top edge |
| Log | Swipe up |
| Fast forward while held | Keep a finger on the picture (everything, or only read text when Fast forward is "Read") |
| Hide text | Tap with two fingers (any tap shows it again) |
| Pass a movie | Tap (it asks first where a click does) |

The control panel is the quick bar at a finger's size: the same fifteen buttons, the game's own plates at one and a half times their size in three rows of five, each with its name under it. A tap on a plate does it and sends the panel up; a tap anywhere else, or a swipe up, only sends it up. The first time a story starts, a band across the top names the gestures until the panel has been pulled down once.

A choice takes two taps, as the game's own touch screen did: the first lights the row, a tap on the lit row takes it. Yes / No questions are drawn larger and answer at one tap.

In the menus whatever is pressed lights up, and its tap chooses it. Lists move under the finger. Back is the game's own touch Back button, which slides in at the bottom right of every screen that has a way back (on a question it is No). There is no hint bar along the bottom on a touch device.

- **Title.** The logo is smaller and the rows twice their size under it.
- **System menu, Save, Load.** The column's rows stand further apart. Save rows are a finger's size as they are.
- **Config.** Drawn larger across the whole width, without the column (Back returns to it). A slider follows a finger that moves along it, and a tap on its bar puts the knob there; a finger that moves up or down scrolls the page instead. Minus and plus step at a tap and repeat when held. The Controls page lists these gestures in place of the keys.
- **Log.** Tap a line for Quick Jump, and the speaker mark at its left to hear its voice again. Pulling on up past the newest line closes it.
- **Gallery.** In the CG viewer a tap or a swipe to the left goes to the next picture and a swipe to the right to the one before; two fingers zoom, up to four times the fitted size, and one moves a picture that has been made larger. The viewer's Back button leaves two seconds after the last touch and returns at the next. In the flowchart a tap on a scene shows it at the right, and a tap on the scene shown opens it.

All of it is made from the game's own interface art: the Back button, the panel's plates and strip, the notice window and the auto mode's ring on the rotate screen, the speaker mark in the log. Story playback is the same on every device. Tried on a phone (Android 17, in Chrome and in the app) and in Chrome's touch emulation at 390 x 844 upright and 667 x 375, 844 x 390, 932 x 430 and 1024 x 768 in landscape.

### Controller

A controller works as a second way to play: A advances and chooses, B cancels or stops skipping, Y opens the system menu, X the log, up the quick bar, down advances, R skips, L is auto (the config's page after / before in the menus), ZR fast forwards while held and ZL rewinds. The right stick moves the cursor in the menus as the D-pad does, and the left stick scrolls.

## How it plays

### The opening page

The game opens on the same page every time, for everyone (`app/js/home.js`). It is built from the game's art: the mode panel's strip with four of its plates relettered (ABOUT, GITHUB, DOWNLOAD, PLAY ONLINE), over Config's inner panel. Each plate shows its own page:

- **ABOUT**: what this project is and how it was made, from decompiling the game to testing the port against it (the sections are in `app/js/welcome.js`).
- **GITHUB**: what is in the repository, and a link to it.
- **DOWNLOAD**: the game as an app that needs no connection. Windows and Android each have what the app needs, how to install it, and its download; macOS and Linux have the steps to build the same app from the source.
- **PLAY ONLINE**: what the browser version needs, and the title's PRESS ANY BUTTON. A click or tap on that page, or Enter, starts the game. Browsers play no sound until the page has been clicked, so this press is that click, and the game opens with its sound on. On a touch device the page also says how to play by touch.

It opens with no tab chosen, showing the game's logo and a line naming the plates, so a stray tap starts nothing. It is skipped only inside the Android and desktop apps, which are the game itself, and for an address that opens a scene (`?script=...`).

### Saves

100 save slots, a quick save, and 39 automatic saves. As in the game a save holds the latest checkpoint (a scene's start, a choice, or the first line of a page), so loading shows that page from its first line. The automatic save is made when you return to the title from the system menu (which asks nothing outside a gallery replay), and here also when the page is closed during a story, or the Android app is left, or the desktop app is closed. The save screen lists all 100 slots by number, starting on the lowest empty one. The load screen lists everything there is to load, newest first: the slots in use, the quick save and the automatic saves, each named. Continue loads the save written last. In the story's Save and Load, Left gives the menu's column the cursor and Right gives it back to the row you were on. Some chapters ask "Save Progress?"; Yes opens the save screen and the story goes on when it closes.

Saves and progress are kept in the browser, so clearing its site data removes them, and another browser starts empty. A save of an ordinary scene is about 13 KB; the browser allows about 5 MB in all.

On the very first start (before the prologue has played) the game opens straight on the opening movie, which asks before it can be passed ("Skip intro video?"); the title, its cautions and the story follow. After that it starts with the logos and the notice, and New Game goes straight to the story.

### Skipping and rewinding

Skipping waits at text you have not read when Fast forward is "Read" (the default) and goes on by itself at read text; on "Full" it passes everything. Choices do not turn it off; the Skip key or button does (the pad's B too), and so does opening the system menu.

Rewinding (and the log's Quick Jump) goes back up to 800 points in the current session; loading a save starts the trail again. What has been read is kept in the browser from now on, so text read before this existed counts as unread. Quick load asks first, as the game does, and shows the quick save's picture.

### Movies

The movies are MP4 files with AV1 video (SVT-AV1 at constant quality 24, from the game's H.264) and the game's own AAC sound, copied without re-encoding. Every frame keeps its place and time. All 45 are AV1, 0.42 GB where the game's are 1.76 GB. No movie may be over 95 MB, so that no file in `web/` is too large for a host such as GitHub; one that would be is made at a coarser quality until it fits, which `ed03_ciel` and `op2_ciel` needed.

The two opening songs cannot be passed the first time they play; after that a click or key asks "Skip opening animation?", in the gallery too. The end credits ask "Skip Outro?" every time. The prologue asks "Skip intro video?" on its first showing and passes without asking after that. Each question starts on No and holds the movie while it is up. The system menu does not open over a movie.

### Ciel-sensei and endings

After a bad end the game offers its "Teach Me, Ciel-Sensei!" episode: a card, then "Enter hint corner (No. n)?". Yes plays the episode and then returns to the title; No returns to the title at once. The Ending List in the gallery lists the episodes begun, and endings reached before this version could play them are counted once from the scenes completed and text read. Rebuild `gallery.json` with `build_gallery.py` to get the list.

## Under the hood

### Loading

Nothing waits for the whole game: each file is fetched when it is first used, and the ones that will be needed soonest are fetched before that (`app/js/preload.js`).

- **From the opening page on.** While the opening page is up (on later visits, while the logo plays) the game fetches, in this order: what the next screen needs (on a first visit the opening's script, picture and movie; later the logo, the title's art and its movie; the interface sounds and the title's music), then the story's own screen (the text window and its marks, the choices, the questions, the quick bar, the fonts, the first scene's pictures and sounds), then the menus (system menu, log, Save, Load, Config, the speech balloons), then the gallery and flowchart art. At most four of these are read at once, so a file the game asks for itself never queues behind them.
- **As the story runs.** At every message the script is read ahead: the pictures, sound effects, music and voices of the next 300 commands (about a dozen messages), and from 2,500 commands away the movies and the scripts it can jump to, which are read on from where they start. Voices are left out while skipping or switched off.
- **Movies.** A movie that is coming is given a player of its own, which starts reading the file as a browser reads any movie. When the movie plays, that player takes the place of the page's, so it starts at once from what has been read. Two are kept ready at most. The title's movie is made ready again whenever the title is about to come back (a story's end, Return to Title, the gallery).
- **Sounds in packs.** The 16,460 voices, 1,284 sound effects and 9 interface sounds are also kept in 658 packs of about 1.5 MB (`assets/pack`, made by `tools/build_packs.py`): the files end to end as they are, in the order the story first uses them, so the pack with a line's voice has the next lines' too. The game asks for the pack and cuts each sound from it, which is about 27 times fewer requests than a file a sound. A pack is named by a hash of its content, so a browser can keep it for good; `assets/pack/index.json` names the index in use. Music and movies are not packed. Where there are no packs, or a pack cannot be read, each sound is read from its own file. The repository carries the voices and sound effects as packs alone; the loose files, which `build_packs.py` makes the packs from, come from `convert_all.py` and stay with whoever builds the assets.
- **After PLAY ONLINE.** On a first visit, pressing PRESS ANY BUTTON brings the game's "Loading" window with a count, until what the next screen and the story's first screen use has been read and the first movie can start. It is not shown when that is so already, and it never holds longer than 20 seconds.

What has not arrived when it is wanted is fetched then.

### Fonts

SeuratPro and Inter are always used from the page's own files. Every other font is looked for on the system first, in the order given. Where none of a row's fonts is installed, a free backup that ships in `app/fonts/` is used instead (the last column), so text never falls to a generic face. The backups have names of their own ("Gelasio Bundled" and so on), so they never take over from an installed font. They hold Latin, accents and punctuation only: Japanese and symbols come from the system, which always has them. Gelasio has Georgia's widths and Arimo has Arial's, so lines break where they would. Each backup's licence is beside it (SIL OFL, the Ubuntu Font Licence, the GUST Font License). Letters drawn on canvases (the plates, the config's words) wait at start for any backup they will need (`main.js` `CANVAS_FONTS`), and a system that has the fonts fetches nothing.

| Font | Used for | Then | Backup (included) |
|---|---|---|---|
| Georgia | The story, choices, the log, Yes / No questions | Times New Roman | Gelasio |
| SeuratPro M | Speech balloons (`assets/fonts/`, the game's own) | Georgia | Gelasio |
| Inter | Gallery lists, Music Player, the hints, Controls page (`app/fonts/`) | | (included itself) |
| Helvetica | Flowchart cards, the config's words | Arial | Arimo |
| Apple Chancery | Chapter names, the story's old-fashioned lettering | Lucida Calligraphy, Monotype Corsiva, URW Chancery L, TeX Gyre Chorus | TeX Gyre Chorus |
| Hoefler Text | Day numbers beside chapter names | Palatino Linotype, Palatino, Book Antiqua | TeX Gyre Pagella |
| PT Sans Narrow | The words on the plates | Ubuntu Condensed, Arial Narrow | PT Sans Narrow |
| Ubuntu Condensed | Chapters on save rows and the flowchart | PT Sans Narrow, Arial Narrow, Roboto Condensed | Ubuntu Condensed |
| Ubuntu | The day on a save row | Helvetica Neue, Segoe UI | Ubuntu Light |
| Eurostile | The Audio Track label | Microgramma, DIN Alternate, Bahnschrift | Inter |
| System font | Scene names in the menus, short notices | | (the system's own) |

The game itself carries `ja/TT_TsukuMin-D.ttf`, `ja2/TT_TsukuGo-D.ttf`, `ja3/FOT-SeuratPro-M.otf`, `ja3/SeuratPro-M.otf` and `exfont_nx01.bffnt`.

### Opening a particular scene

Add these to the address:

| | |
|---|---|
| `/?script=00_02` | Opens that script by name (capitals matter) |
| `/?script=89` | The same by its number, 0 to 548 |
| `/?script=04_00_ARC04_4_1&pc=500` | Runs through to command 500, then plays normally |
| `/?script=04_00_ARC04_3&label=LBL_008` | Starts at a label inside the script. Nothing before it has run, so the screen stays empty until the scene next draws a picture |
| `&mute` | No sound at all, with any of these |

Script names start with the day, then 00 for Arcueid's route or 01 for Ciel's: `04_00_ARC04_10`, for one, is the last scene of Arcueid's fourth day. `00_00` to `00_02` are the prologue and `QA_01` to `QA_24` the Teach Me, Ciel-sensei episodes; all 549 are in `assets/scripts/index.json`. A scene opened this way starts with the story's flags empty, so one that depends on earlier choices can branch differently than in play. It also skips the opening page, so sound begins at your first click.

## The repository

| Folder | What is in it |
|---|---|
| `web/` | The game as served: `app/` (engine, interface, styles, fonts), `assets/` (the game's converted files) and `server.py`. It runs by itself. |
| `web-dev/` | What makes and checks it: `tools/` (conversions from a game dump), `tests/`, `smoketest/`, `audit/` (the parity audit and the function map), `android/` (the Android app), `ios/` (the iPhone app), `desktop/` (the Windows, macOS and Linux app) |
| `web-research/` | The first size research and its tools ([FINDINGS.md](web-research/FINDINGS.md)) |

Tests, with Node.js and no packages: `node --test web-dev/tests/*.test.mjs`. Every script at full speed, listing errors: `python3 web-dev/tools/dev_server.py 8770`, then open http://localhost:8770/smoketest.html. What the parity audit in `web-dev/audit/` found and what changed is in [FIXES.md](web-dev/audit/FIXES.md).

### The files

**Engine (`web/app/js/`)**

- `vm.js`: script commands
- `textbox.js`, `audio.js`, `main.js`: text, sound, input and settings
- `renderer.js`: layers, blur, blend modes, crossfades; `transform.js`: where a layer goes (parents, pivots, panel clips and links)
- `animation.js`: the game's motion tracks, interpolation and animation clock
- `effects.js`: screen and layer shake, ambient sway and text shake; `screenfx.js`: the RGB split, speed lines and film grain
- `random.js`: the game's `rand()`, which a sway and the speed lines draw from
- `reflow.js`: takes out the English patch's forced line breaks, so the text box wraps the lines itself
- `preload.js`: what is fetched before it is asked for (see [Loading](#loading))

**Interface (`web/app/js/`)**

- `ui.js`: the game's screens, drawn with its interface art; `uifx.js`: what moves on them, timed as the original (the title's fade, logo, glow, dust, background and music by progress, the cautions, the system menu's fade, background bands, sparkles and cursor)
- `home.js`: the opening page; `welcome.js`: its ABOUT tab's text
- `gallery.js`, `unlocks.js`, `endings.js`: the title's GALLERY as the game has it (CG Gallery, Music Player, Flowchart, Movie, Ending List). The CG and music tables are read from the executable; a picture unlocks when it is shown (or by STCG), a track when it is played, a movie when it is played. The Ending List shows an ending or bad end once its "Teach Me, Ciel-Sensei!" episode has begun, and plays the episode again ([ANIMATIONS.md](web-dev/ANIMATIONS.md#endings-and-ciel-sensei))
- `flowchart.js`, `flowchart-model.js`: the flowchart, from the game's own rows, links, titles, notes and thumbnails. Scenes appear once played; scenes that every path to a played scene must pass count as played too
- `chapters.js`: the chapters' days and names, as text; `confart.js`: the config's System page with its words at one size
- `keys.js`: the keyboard map; `touch.js` with `touch.css`: the touch interface; `touchfx.js`: the ring drawn where the screen is clicked

**Tools (`web-dev/tools/`)**

- `build_core.py`: scripts, dialogue and tables; `build_images.py`: how large each image needs storing
- `convert.py`, `convert_all.py`: images to AVIF, voices and music to Ogg Opus without re-encoding, sound effects to Opus, the movies' pictures to AV1 with their sound copied, the balloon font copied
- `needed.py`, `check_assets.py`: what the game can ask for, and whether it is all there; `build_packs.py`: the voices and sounds in packs
- `build_ui.py`: the game's interface art (and the film grain static; `build_ui.py "$PWD" NOISE_PARTS` adds just that; `PARTS`, the start-up notice and cautions from `parts.hed`, likewise)
- `build_animations.py`, `build_effects.py`: the game's motion tracks and colour effect presets
- `build_gallery.py`, `build_flowchart.py`, `native_flowchart.py`, `build_system.py`, `build_sounds.py`: the gallery, flowchart and system tables, and the interface's own sounds
- `decode_save.py`: reads a save of the original game and prints its progress as the web version keeps it

### Making the assets again

Only if `web/assets/` has to be rebuilt. From the repository root, with the dump in place, the patch in `mods/japan`, the packages in `web-research/.venv` and `ffmpeg` on the path, built with `libsvtav1` (the movies are encoded with it):

```bash
web-research/.venv/bin/python -I web-dev/tools/build_core.py "$PWD"
web-research/.venv/bin/python -I web-dev/tools/build_images.py
web-research/.venv/bin/python -I web-dev/tools/build_ui.py "$PWD"
web-research/.venv/bin/python -I web-dev/tools/build_flowchart.py
web-research/.venv/bin/python -I web-dev/tools/build_gallery.py "$PWD"
web-research/.venv/bin/python -I web-dev/tools/build_system.py "$PWD"
web-research/.venv/bin/python -I web-dev/tools/build_sounds.py "$PWD"
web-research/.venv/bin/python -I web-dev/tools/convert_all.py "$PWD" --jobs 6
python3 -I web-dev/tools/build_packs.py
python3 web-dev/tools/check_assets.py
```

`convert_all.py` makes what `tools/needed.py` lists: what the port can ask for, and nothing it makes for itself, so not the game's pre-blurred pictures. It is safe to stop and resume. `check_assets.py` says whether anything is missing.

The core build also exports the original engine's motion tracks and colour effect presets (`STEC`). To add them to an existing web copy:

```bash
web-research/.venv/bin/python -I web-dev/tools/build_animations.py "$PWD"
web-research/.venv/bin/python -I web-dev/tools/build_effects.py "$PWD"
```

These need the Japanese port's prepared `data/tsuki/analysis/main.bin` and `data/tsuki/gen/main`; the exporter checks the image's fingerprint before reading its tables. Motion, shake and sway run in the browser; see [ANIMATIONS.md](web-dev/ANIMATIONS.md) for command coverage and remaining differences.

## Credits

- **The game.** The Tsukihime remake, *Tsukihime -A piece of blue glass moon-*, and all of its story, art, music and voices belong to TYPE-MOON, Aniplex and the other rights holders. This project is unofficial and non-commercial, and is not affiliated with or endorsed by them. Please support the official release.
- **English text.** The English script comes from the Tsukihimates fan translation patch.
- **Built on.** The native port this grew from is based on the SuperMarioWonderRecomp recompilation framework by BelmanteGu. Ryujinx's shader translator was used offline; Ghidra for decompilation; FFmpeg, SVT-AV1 and Pillow for the conversions.
- **Fonts.** Inter, Gelasio, Arimo and PT Sans Narrow under the SIL Open Font License; Ubuntu and Ubuntu Condensed under the Ubuntu Font Licence; TeX Gyre Chorus and Pagella under the GUST Font License. Each licence is beside its font in `web/app/fonts/`.
- **How it was written.** Built with Claude, Anthropic's AI model, under human direction: the goals, the decisions and the playing and judging of every result were human, and most of the code was written by the AI.
