// main.js - the game's window: input, the frame loop, settings, saving; the screens themselves are in ui.js.
import { TouchFx } from "./touchfx.js";
import { installTouch } from "./touch.js";
import { relettered } from "./confart.js";
import { Renderer } from "./renderer.js";
import { Audio } from "./audio.js";
import { TextBox } from "./textbox.js";
import { VM, markSaved } from "./vm.js";
import { QUICK_BAR, UI } from "./ui.js";
import { KeyMap, keyName } from "./keys.js";
import { advanceRandom, textShakePixels } from "./effects.js";
import { openFlowchart } from "./flowchart.js";
import { openGallery, preloadGallery } from "./gallery.js";
import { welcomeDue, markWelcomed } from "./welcome.js";
import { openHome, homeDue } from "./home.js";
import { Preloader, RANK, movieUrl } from "./preload.js";
import { REWIND_FIXED, ROUTE_FLAGS, fvar } from "./flowchart-model.js";
import { CLICK_MARK, STORY_MOVIES, TITLE_MOVIE_LOOP, movieLook, movieQuestion, nextTitleStage, titleMusic as titleTrack, titleVariant } from "./uifx.js";

const $ = (id) => document.getElementById(id);
const stage = $("stage");
// A device played by touch (touch.js): its listeners go in before any other, and it fits the stage inside the safe area.
const touch = installTouch();

function fitStage() {
  if (touch.on) { touch.place(stage); return; }
  const k = Math.min(innerWidth / 1920, innerHeight / 1080);
  stage.style.transform = `translate(${(innerWidth - 1920 * k) / 2}px, ${(innerHeight - 1080 * k) / 2}px) scale(${k})`;
}
addEventListener("resize", fitStage);
fitStage();

// The fonts of the letters drawn or measured on canvases: each stack's system fonts, and the backup it comes to where none of them is installed (style.css
// "... Bundled"). Inter is the page's own and always fetched. (ui.js PANEL_ART.text, confart.js CONF_TEXT and flowchart.js TITLE_FONT name them.)
const CANVAS_FONTS = [
  { system: ["Georgia", "Times New Roman"], backup: '400 42px "Gelasio Bundled"' },   // (and the story's dashes, measured once: textbox.js setDashJoin)
  { system: ["PT Sans Narrow", "Ubuntu Condensed", "Arial Narrow"], backup: '400 32px "PT Sans Narrow Bundled"' },
  { system: ["Helvetica", "Arial", "Liberation Sans"], backup: '400 28px "Arimo Bundled"' },
  { system: [], backup: "400 32px Inter" },
];
// Whether the system has a font: text in it measures otherwise than in a generic face that stands in for a missing one.
function installedFont(family) {
  const g = document.createElement("canvas").getContext("2d"), sample = "mmmmmmmmmmlli1WWQ@";
  return ["monospace", "serif"].some((generic) => {
    g.font = `72px ${generic}`;
    const plain = g.measureText(sample).width;
    g.font = `72px "${family}", ${generic}`;
    return g.measureText(sample).width !== plain;
  });
}

// A left press (or a touch) anywhere on the picture draws the game's touch ring there (touchfx.js). Captured before
// any screen's own handler, which may stop the event.
const touchFx = new TouchFx($("touchfx"));
addEventListener("pointerdown", (e) => {
  if (e.button !== 0 || document.documentElement.classList.contains("upright")) return;   // (not on the opening page's upright stage)
  const r = stage.getBoundingClientRect(), k = r.width / 1920;
  const x = (e.clientX - r.left) / k, y = (e.clientY - r.top) / k;
  if (x >= 0 && y >= 0 && x < 1920 && y < 1080) touchFx.touch(x, y);
}, true);

const gfx = new Renderer($("gl"));
const audio = new Audio();
const text = new TextBox();

function toast(msg, ms = 2000) {
  const t = $("toast");
  t.textContent = msg;
  t.style.display = "block";
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => { t.style.display = "none"; }, ms);
}

// The engine's own notices (native 0x3b430 / 0x3b4b0, DISP_PARTS_JA/popup_ja): Auto Save, Quick Save and Auto. The atlas has a Skip
// row too, but no caller passes it: 0x3b430 clamps kinds to 1-3 and the skip toggles make no call (N2-18).
// One pops in at the top left (0, 32 of 640 x 448), its scale following the spring table at 0x572bbc as t rises 0.04 a
// frame at the normal frame step (0x3c970 at 0x3eb34-0x3ebc0: 0.1 is only for a slower step; N2-10), stays until t passes 3
// (75 frames) and shrinks back the same way (25 frames).
const POPUP_CELLS = { autosave: [8, 8], quicksave: [8, 72], auto: [8, 136], skip: [8, 200] };
const POPUP_KEYS = [[0, 1.4], [0.2, 1.23], [0.6, 1], [1.2, 0.8], [1.15, 0.9], [1.1, 0.98], [1.03, 1.06], [1.02, 1.04], [1, 1], [1, 1]];
let popupRun = null;
// 0x3b580: a popup is up. 0x3b480: one that has finished coming up (t >= 1) goes on to its shrinking at once (t = 3).
const popupBusy = () => popupRun !== null;
const popupHurry = () => popupRun?.hurry();
function popup(kind) {
  const cell = POPUP_CELLS[kind];
  if (!cell) return;
  const el = $("popup");
  el.style.backgroundPosition = `${-cell[0]}px ${-cell[1]}px`;
  el.style.display = "block";
  let t = 0, closing = false, first = true;
  const run = { hurry() { if (!closing && t >= 1) t = 3; } };
  popupRun = run;
  // a step each game frame (vm.everyFrame), the first standing still
  vm.everyFrame(() => {
    if (popupRun !== run) return false;
    const dt = first ? 0 : 1;
    first = false;
    t += (closing ? -0.04 : 0.04) * dt;
    if (!closing && t > 3) { closing = true; t = 1; }
    if (closing && t < 0) { el.style.display = "none"; popupRun = null; return false; }
    const x = Math.max(0, Math.min(9, t * 9)), i = Math.floor(x), f = x - i, a = POPUP_KEYS[i], b = POPUP_KEYS[Math.min(9, i + 1)];
    el.style.transform = `scale(${a[0] + (b[0] - a[0]) * f}, ${a[1] + (b[1] - a[1]) * f})`;
  });
}

// ---- settings -------------------------------------------------------------------------------------------------
// The config's system page (native widgets 0x37-0x4d, applied by 0x2a730): unread and read text speed (ms a letter,
// 0-250) each with "Display whole text"; auto mode page switching and click wait (0-10000 ms); read scenes auto skip
// with "Display confirmation"; fast forward (Full or Read); text display (+0x61: letters fade in, or "Insta display"
// shows each whole, for all text) and read text display (+0x62: earlier lines "Fade out" to their dim level, or
// "Insta erasure" takes them there at once); the settings keep their old names, fadeUnread and fadeRead.
// The sound page: voices on or off and whether input stops them; volumes are audio.js's.
// The game's own defaults (the initial config at 0x46b080, which the config's reset also writes, 0x2c810): text 35 and
// 15 ms a letter, auto 3000 / 2200 ms, voices on and stopped by input, no whole-text display, read scenes not skipped
// and no confirmation for it (+0x60 = 0), fast forward "Read" (+0x1e = 1: 0x40ed0 and 0x77790 stop it at unread
// text), letters fading in and earlier lines fading out (+0x61 = +0x62 = 0).
const DEFAULTS = { textSpeed: 35, readSpeed: 15, autoPage: 3000, autoClick: 2200, skipRead: false, voiceOn: true, voiceStop: true,
  wholeUnread: false, wholeRead: false, skipConfirm: false, fastForward: "read", fadeUnread: true, fadeRead: true };
let settings = { ...DEFAULTS };
try { Object.assign(settings, JSON.parse(localStorage.getItem("tsuki.settings") || "{}")); } catch { /* defaults */ }
function setSetting(k, v) {
  settings[k] = v;
  try { localStorage.setItem("tsuki.settings", JSON.stringify(settings)); } catch { /* not saved */ }
  text.speed = settings.textSpeed;
  vm.textSpeed = settings.textSpeed;
  vm.readSpeed = settings.readSpeed;
  vm.wholeUnread = !!settings.wholeUnread;
  vm.wholeRead = !!settings.wholeRead;
  vm.fadeUnread = settings.fadeUnread !== false;
  vm.fadeRead = settings.fadeRead !== false;
  vm.fastForwardRead = settings.fastForward === "read";
  vm.skipRead = !!settings.skipRead;
  vm.skipConfirm = settings.skipConfirm !== false;
  vm.autoPage = settings.autoPage;
  vm.autoClick = settings.autoClick;
  vm.voiceOn = settings.voiceOn;
  vm.voiceStop = settings.voiceStop;
  audio.setVoiceSwitch(settings.voiceOn);   // voiced effects playing follow the switch (0x9b7f0, type-2 channels)
}

// The marks' cell counter (0x572b60) is one for all of them: 0x38ec0 adds the frames while a mark is drawn and takes
// it modulo the drawn kind's loop (cells x 2 frames), so a new mark goes on from the cell the last one stopped at.
let markFrames = 0, markShownAt = null;
function onWait(on, pageEnd) {
  const m = $("click-mark");
  if (markShownAt !== null) { markFrames += ((performance.now() - markShownAt) * 60) / 1000; markShownAt = null; }
  if (!on) { m.style.display = "none"; return; }
  const p = text.endOfTextPos();
  if (!p) return;
  // Native 0x391a0 puts the mark 2 units (6 px) after the end of the text, 3.5 units below it, or 5.5 for the page
  // mark (F799 = 1): 2 units (4.82 px) lower.
  m.style.left = `${Math.min(1840, p.x + 6)}px`;
  m.style.top = `${p.y - 44 + (pageEnd && !text.balloon ? 2 * (1080 / 448) : 0)}px`;
  m.classList.toggle("page", !!pageEnd);
  // In a balloon (styles 3-32) the mark is the third kind, pageBreak_ciel_a, at the text's end plus 4 units across
  // and down (0x391a0): 2 units right of the line mark and half a unit lower (style.css #click-mark.ciel).
  m.classList.toggle("ciel", !!text.balloon);
  const kind = text.balloon ? 2 : pageEnd ? 1 : 0;
  markFrames %= CLICK_MARK[kind].cells * 2;
  m.style.animationDelay = `${-markFrames / 60}s, 0s`;
  markShownAt = performance.now();
  m.style.display = "block";
}

// Firefox on a Mac showed white flashes over the title's movie, on the screen only (its decoded frames measure clean, and the user confirmed this cured it): there
// a movie's element is not drawn, and each new frame is painted onto an opaque canvas of its own over it. The element keeps decoding and playing its sound.
const paintsMovies = CSS.supports("-moz-appearance", "none") && "requestVideoFrameCallback" in HTMLVideoElement.prototype;
let moviePic = null, moviePicRun = 0;
function stopPaintingMovie(v) {
  moviePicRun++;
  if (moviePic) moviePic.style.display = "none";
  v.style.opacity = "";
}
// Not in Firefox on Android: there a movie's frames, decoded by the device, come out black when drawn to a canvas (only the sound was left, 2026-11-10),
// and the flashes this was made for were a Mac's. The element is drawn as it is.
const paintsNothing = /Android/i.test(navigator.userAgent || "");
function paintMovie(v) {
  stopPaintingMovie(v);   // nothing of the last movie
  if (paintsNothing) return;
  if (!moviePic) {
    moviePic = document.createElement("canvas");
    moviePic.id = "movie-pic";
    moviePic.width = 1920; moviePic.height = 1080;   // the size of every movie in the game
    moviePic.g = moviePic.getContext("2d", { alpha: false });
    v.after(moviePic);
  }
  const run = ++moviePicRun;
  const step = () => {
    if (run !== moviePicRun) return;
    moviePic.g.drawImage(v, 0, 0, 1920, 1080);
    if (moviePic.style.display !== "block") { moviePic.style.display = "block"; v.style.opacity = "0"; }   // from its first picture
    v.requestVideoFrameCallback(step);
  };
  v.requestVideoFrameCallback(step);
}

// The element a movie plays in. One that has been reading the file in advance (preload.js readyMovie) takes the place of the page's, with what that one was
// styled with, so the movie starts from what has been read; else the page's own starts on the file.
function movieElement(name) {
  const old = $("movie"), made = preload.takeMovie(name);
  if (!made) { old.src = movieUrl(name); return old; }
  stopPaintingMovie(old);
  old.onended = old.onerror = null;
  old.pause();
  old.removeAttribute("src");
  old.load();
  old.removeAttribute("id");
  made.id = "movie";
  made.style.cssText = old.style.cssText;
  old.replaceWith(made);
  return made;
}
// The title's movie at its stage (uifx.js titleVariant), and the stage the title will be at when it is next entered: it moves a step each time (ui.title).
const titleMovie = (stage = ui.titleStageNow()) => `titlebg${titleVariant(stage)}`;
const titleNext = () => nextTitleStage(ui.titleStageNow(), vm.flow.started);

let moviesDone = null;
function movieCover() {
  let c = $("movie-cover");
  if (!c) { c = document.createElement("div"); c.id = "movie-cover"; (moviePic || $("movie")).after(c); }
  return c;
}
// opts.story: a TOMP movie, opts.number its number, opts.seen whether it has been seen before (G005).
// opts.music: { at, n } plays music n once the movie has run `at` seconds (the gallery's prologue: 2 at 360 s, 0x19040).
function playMovie(name, opts = {}) {
  return new Promise((res) => {
    // A test jump and the smoke test pass movies; the story's own run even while skipping.
    if (vm.skip && (!opts.story || vm.skipUntil || !vm.skipPaced)) { res(); return; }
    movieClicks = !name.startsWith("phasetitle_");
    const v = movieElement(name);
    v.style.display = "block";
    if (paintsMovies) paintMovie(v);
    v.loop = false;
    v.titleLoop = false;
    v.volume = audio.vol.bgmMute ? 0 : Math.max(0, Math.min(1, audio.vol.bgm));   // movies play at the music volume
    v.muted = !!audio.muted;
    // Skip and auto are put aside while a story movie plays (0x402a0) and come back after it (0x40a00); the fast-forward key, read every frame, comes back by
    // itself (syncFastForward, N2-208, N2-209).
    const modes = opts.story ? { skip: vm.skipToggle, auto: vm.auto } : null;
    if (modes) { if (vm.skipOn) setSkip(false); if (vm.auto) setAuto(false); }
    const look = opts.story ? movieLook(opts.number) : null;
    const rule = opts.story ? STORY_MOVIES[opts.number] : null;
    // the gallery lists a movie only once it has been seen, the prologue aside, which asks nothing there
    movieAsk = movieQuestion(opts.number, !!opts.gallery || !!opts.seen || (!!rule && !!((vm.getVar("G005") >> rule[0]) & 1)));
    const cover = look ? movieCover() : null;
    let alpha = look && look.fadeIn ? 0 : 1, frames = 0, passing = false, music = false, chimed = false, last = null, ended = false;
    if (cover) { cover.style.background = look.white ? "#fff" : "#000"; cover.style.display = "block"; cover.style.opacity = String(1 - alpha); }
    const prologueMusic = () => { if (!music && opts.number === 4) { music = true; audio.playBGM(2, {}); } };
    const cue = opts.music;
    const listen = () => { if (cue && v.currentTime >= cue.at) { v.removeEventListener("timeupdate", listen); audio.playBGM(cue.n, {}); } };
    if (cue) v.addEventListener("timeupdate", listen);
    const finish = () => {
      v.removeEventListener("timeupdate", listen);
      v.pause();
      v.removeAttribute("src");
      v.load();
      v.style.display = "none";
      stopPaintingMovie(v);
      v.onended = v.onerror = null;
      if (cover) cover.style.display = "none";
      moviesDone = null;
      movieCanPass = null;
      movieAsk = null;
      // The movie has ended or been passed: only now does it count as seen (0x40a00 -> 0x923c0 at 0x40af8 is G005's one writer, N2-171).
      if (rule) vm.setVar("G005", vm.getVar("G005") | (1 << rule[0]));
      if (opts.story) { vm.unlocks.watched(name); vm.unlocks.save(); }
      if (modes) {
        if (modes.auto) { vm.auto = true; $("mode-auto").style.display = "block"; vm.armAuto(); }
        if (modes.skip) { vm.skipToggle = true; vm.skip = true; vm.forceSkip = false; $("mode-skip").classList.add("on"); }
      }
      res();
    };
    moviesDone = () => {
      if (!look) { finish(); return; }
      if (passing) return;
      passing = true;
      prologueMusic();
    };
    movieCanPass = look ? () => !rule || opts.seen || !!((vm.getVar("G005") >> rule[0]) & 1) : null;
    v.onended = v.onerror = () => { ended = true; if (!look) finish(); };
    if (look) {
      const step = (now) => {
        if (!moviesDone && !passing) return;
        const dt = last === null ? 0 : Math.min(10, ((now - last) * 60) / 1000);
        last = now;
        if (v.readyState >= 2 && !v.paused) frames = Math.floor(v.currentTime * 60);
        if (look.chime !== null && !chimed && frames >= look.chime && v.readyState >= 2) { chimed = true; audio.playSys(7, "se"); }
        if (opts.number === 4 && frames > 21599) prologueMusic();
        if (passing) alpha = Math.max(0, alpha - dt / 60);
        else if (frames >= look.leaveAt || ended) alpha = look.fadeOut ? Math.max(0, alpha - dt / look.fadeOut) : 0;
        else if (look.fadeIn) alpha = Math.min(1, alpha + dt / look.fadeIn);
        cover.style.opacity = String(1 - alpha);
        if (opts.number === 5 && frames >= 60) cover.style.background = "#000";
        if ((passing || ended) && alpha <= 0) { finish(); return; }
        requestAnimationFrame(step);
      };
      requestAnimationFrame(step);
    }
    // Before the first click a browser refuses to start a movie with sound: it then plays muted rather than not at all.
    v.play().catch((e) => {
      if (e && e.name === "NotAllowedError" && !v.muted) { v.muted = true; v.play().catch(() => { ended = true; if (!look) finish(); }); } else { ended = true; if (!look) finish(); }
    });
  });
}

// A movie that may be passed only once it has played this long (seconds); 0: at once. A story movie also asks
// movieCanPass (STORY_MOVIES). A click does not pass a phase title in the game (movieClicks; the keys still do).
let movieMinTime = 0, movieCanPass = null, movieClicks = true, movieAsk = null, movieAsking = false;
// A movie with a question (uifx.js movieQuestion) asks it, starting on No, before a try to pass it goes through (a port addition), the movie held under it.
const askingSkip = () => !!moviesDone && !!movieAsk;
const passMovie = async () => {
  if (!moviesDone || movieAsking || $("movie").currentTime < movieMinTime) return;
  if (!movieAsk) { if (!movieCanPass || movieCanPass()) moviesDone(); return; }
  const v = $("movie");
  v.pause();
  movieAsking = true;
  const yes = await ui.confirmSystem(movieAsk, { startNo: true });
  movieAsking = false;
  if (!moviesDone) return;
  v.play().catch(() => {});
  if (yes) { movieAsk = null; moviesDone(); }   // nothing more to ask while it fades out
};

// Start-up, as native 0xb5650 runs it before the title: movie 38 (TM_CI) over white, which a press passes once it
// has played 120 frames (table 0x3c98fc, checked against the movie's own time, 0x1ae0), then the notice (ui.notice).
// Only once the prologue (scene 485) has started (0xb5f30, G140 bit 5): on the very first launch there are no logos and
// no notice, and the opening starts at once (the title's 0x8d2f0 -> 0x48ac0 starts 00_01 when 485 has not started).
// firstLaunch is the per-boot flag 0xac0de0: set at boot, cleared there when 485 has started, and by the cautions that
// end the first launch's title (0xb5620).
let firstLaunch = true;
async function boot() {
  if (firstLaunch) return false;
  $("movie").style.background = "#fff";
  movieMinTime = 2;
  await playMovie("TM_CI");
  movieMinTime = 0;
  $("movie").style.background = "";   // asked for again: the movie may have brought its own element (movieElement)
  await new Promise((res) => ui.notice(res));
  return true;
}

const vm = new VM({
  gfx, audio, text, onWait, playMovie, toast,
  // The skip toggle stays on through choices and the story's questions (0x83e50 clears it there only with config +0x2c,
  // which is 0 and no setting changes); they wait for the player all the same.
  onChoice: (list) => ui.choices(list),
  onConfirm: (question) => ui.confirm(question),
  onChoiceCancel: () => { if (ui.cancelChoice) ui.cancelChoice(); },
  onSkipEnd: () => setSkip(false),
  popup: { busy: popupBusy, hurry: popupHurry },
  // SELA: "Save Progress?" as the story asks it; Yes opens the save screen, and the story goes on when it closes.
  onAskSave: (question) => ui.askSave(question),
  // RDAS with "Display confirmation": "Jump to Next Scene?" (dialog 10) before the instant run.
  onSceneSkip: (confirm) => (confirm ? ui.confirmSystem(vm.system?.messages?.["232"] || "Jump to Next Scene?", { startNo: true }) : Promise.resolve(true)),
  onCountdown: countdownFrame,
  onLock: (on) => lockControls(on),
});
vm.externalTicks = true;   // the frame loop below steps the game's frames (vm.tick)
vm.useFrameTime();         // and the story's clocks with them, a whole frame at a time (TODO items 123, 146)
// What is read before it is asked for (preload.js): the start-up list from the first page on, and what the script is coming to.
const preload = new Preloader({ vm, gfx, audio });
vm.ahead = (script, pc) => preload.ahead(script, pc);

// XSTP .. XRSM: no skipping, auto mode, menus or rewinding, and the screen kept awake (native 0x40b70 calls
// nn::oe::SetUserInactivityDetectionTimeExtended(true)). 0x40b70 keeps the skip toggle and auto (0xae0660 / 0xae0650)
// and clears them; XRSM's 0x40c60 puts them back.
let wakeLock = null, lockedModes = null;
function lockControls(on) {
  if (on) {
    lockedModes = { skip: vm.skipToggle, auto: vm.auto };
    setSkip(false);
    setAuto(false);
    ui.closePanel();
    navigator.wakeLock?.request("screen").then((w) => { wakeLock = w; }).catch(() => {});
  } else {
    wakeLock?.release().catch(() => {});
    wakeLock = null;
    const m = lockedModes;
    lockedModes = null;
    if (m?.auto) { vm.auto = true; $("mode-auto").style.display = "block"; vm.armAuto(); }
    if (m?.skip) { vm.skipToggle = true; vm.skip = true; vm.forceSkip = false; $("mode-skip").classList.add("on"); vm.advance(); }
  }
}

// ---- frame loop -----------------------------------------------------------------------------------------------
let lastFrame = null, lastDrawn = false;
// The black over the picture during a scene skip's countdown (native 0x3f110 sets its level, 0x3ef20 draws it after
// the scene, under the popups and the skip indicator, 0x3c510): each countdown frame sets the level to 1.5 + v / -30
// (v the frames left after it) and shows the indicator's ">>|" (0x3b5b0(4)); it is drawn at min(level, 1) and falls
// 0.04 a frame, so after the run the screen stays black about 12 frames and comes back over 25.
let skipBlack = 0;
function countdownFrame(v) {
  skipBlack = 1.5 + v / -30;
  const m = $("mode-skip");
  if (!m.classList.contains("countdown")) m.dataset.before = m.className;
  m.classList.add("on", "countdown");
}
function drawSkipBlack() {
  let el = $("skip-black");
  if (!el) {
    if (!(skipBlack > 0)) return;
    el = document.createElement("div");
    el.id = "skip-black";
    stage.insertBefore(el, $("popup"));
  }
  el.style.opacity = String(Math.max(0, Math.min(1, skipBlack)));
  if (skipBlack > 0) skipBlack = Math.max(0, skipBlack - 0.04);
  // the indicator goes back to what the skip toggle shows once the countdown's black starts to lift
  const m = $("mode-skip");
  if (m.classList.contains("countdown") && !(skipBlack > 1)) m.className = m.dataset.before || "";
}
// A countdown of n frames (the scene skips' 4 or 20, 0x40ed0 states 3 and 6), one step a game frame.
async function countdown(n, back = false) {
  for (let v = n - 1; v >= 0; v--) {
    if (back) backIcon(1); else countdownFrame(v);
    await vm.nextFrame();
  }
  if (back) backIcon(0);
}
// The rewind indicator (N2-9): 2 is << while the rewind runs, 1 is |<< during Return to Previous Scene's countdown, 0 hides
// it. Its level moves 0.25 a game frame (0x3b5f0: 0.05 x 5 while 0xae05b8 is set), up on a frame that rewinds and down on the
// others: on native frames one tap of the rewind button shows << for a single frame at a quarter (57 of 223), and a held
// button, which rewinds a page a frame, brings it to full in four frames and takes it out in four.
let backLit = 0, backLevel = 0;   // frames it stays lit (Infinity: until it is hidden); its level, 0-1
// frames: how many game frames it stays lit before it goes out by itself (0: until it is hidden).
function backIcon(state, frames = 0) {
  const m = $("mode-back");
  if (!state) { backLit = 0; return; }
  m.classList.toggle("choice", state === 1);
  backLit = frames || Infinity;
}
// One frame of the rewind indicator (0x3b5f0): up 0.25 on a frame it is lit, down 0.25 on the others.
function backIconFrame() {
  const lit = backLit > 0;
  if (lit && backLit !== Infinity) backLit--;
  if (!lit && backLevel <= 0) return;
  backLevel = Math.max(0, Math.min(1, backLevel + (lit ? 0.25 : -0.25)));
  $("mode-back").style.opacity = String(backLevel);
}

// The text window's pictures for the renderer (item 116), hidden and faded as the page's own elements are: not with the text hidden
// or in the backlog, and going with the system menu's rise (--under-menu). The text shake moves the first, as it does #panel.
function windowPictures(tx, ty) {
  const c = stage.classList;
  if (c.contains("notext") || c.contains("in-log")) return [];
  const k = c.contains("menu-blur") ? Math.min(1, Math.max(0, Number(stage.style.getPropertyValue("--under-menu")) || 0)) : 1;
  return text.pictures().map((p, i) => ({ ...p, alpha: p.alpha * k, dx: i === 0 ? tx : 0, dy: i === 0 ? ty : 0 }));
}

// The game's frames in a display frame of dt: one on a 60 Hz display, one on every second frame of a 120 Hz one, two on a 30 Hz one, and
// so on. A display frame within a quarter of a whole one counts as it. A stall gives as many as it lasted (the game's own clock takes up to
// half a second from a frame, 0xef08c), but a gap of over a quarter of a second is the page not drawing at all (the touch layer's rotate
// screen holds the frames), not a slow frame, and counts as one.
let frameDebt = 0;
function gameFrames(dt) {
  if (dt > 15) { dt = 1; frameDebt = 0; }
  frameDebt += dt;
  const n = Math.floor(frameDebt + 0.25);
  frameDebt -= n;
  return n;
}

async function frame(real) {
  const dt = lastFrame === null ? 0 : Math.min(30, ((real - lastFrame) * 60) / 1000);
  lastFrame = real;
  syncFastForward();
  $("mode-skip").classList.toggle("paused", !!vm.skipPaused);   // state 5: skipping stopped at unread text (0x41944)
  vm.voiceHeldCut();   // the fast-forward key held cuts the line's voice each frame (0x802c0, N2-81)
  // The game's frame (0x48ac0): the script's step and its timers (0x40ed0), the layers, then the window (0x38d40), then the draw. Under fast
  // forward each is worth 33 to the layers and the window (vm.tick, TextBox.tick's step; TODO item 110). The story's clocks move a whole frame at
  // the start of each (vm.frameStep), and the script takes its step before the frame goes on, so a display frame that carries two game frames
  // (30 Hz, or a stall) runs them as two (TODO item 123). Only a display frame with a game frame in it is drawn: the game draws 60 a second
  // whatever the display, and between two of its frames a 120 or 144 Hz display shows the last one again.
  const n = gameFrames(dt);
  for (let i = 0; i < n; i++) {
    if (i) await vm.settleScript();   // what the last frame's tick let go on: its step begins this frame
    vm.frameStep();
    await vm.settleScript();
    vm.tick();
    text.tick(1, vm.stepFrames);
    advanceRandom(vm.allLayers().values(), gfx.lines, gfx.focusLines, vm.now());   // the sways' and speed lines' numbers, in the game's order (item 143)
    drawSkipBlack();
    backIconFrame();
    vm.endFrame();
  }
  pollGamepads(real);
  if (!n && lastDrawn) { ui.panelTick(); requestAnimationFrame(frame); return; }
  lastDrawn = true;
  const now = vm.now();
  gfx.drawLayers([...vm.layers.values()], now, vm.layers);
  gfx.setMenuBlur(stage.classList.contains("menu-blur"), real);
  const [tx, ty] = textShakePixels(gfx.textShake, now);
  gfx.windowPics = windowPictures(tx, ty);
  gfx.present(now);
  stage.classList.toggle("canvas-window", gfx.windowReady);
  $("text").style.transform = $("panel").style.transform = `translate(${tx}px, ${ty}px)`;
  ui.panelTick();
  requestAnimationFrame(frame);
}

// No sound from a page nobody is looking at.
document.addEventListener("visibilitychange", () => {
  vm.holdClocks("hidden", document.hidden);
  lastFrame = null;   // no catching up on the time the page was hidden
  if (!audio.ctx) return;
  if (document.hidden) audio.ctx.suspend();
  else if (!touch.held) audio.ctx.resume();   // not under the rotate screen (touch.js)
});
// Leaving the page while a story runs counts as leaving the story: the automatic save is made, as native makes it on
// returning to the title (0x4cea0 -> 0x52aa0).
addEventListener("pagehide", () => { autosave(); vm.saveRead(); vm.unlocks.save(); if (audio.ctx) audio.ctx.close(); });
// The Android app (web-dev/android) calls this when it goes to the background, where Android may end it without a
// pagehide: the same saves, with the sound left open for coming back. Nothing on the web calls it.
globalThis.appSuspend = () => { autosave(); vm.saveRead(); vm.unlocks.save(); };

// Ordinary skipping passes only text already read; a forced skip passes everything up to the next choice.
// The skip toggle is bit 1 of 0xae0660 (vm.skipToggle): an instant run takes the flags over until it ends (N2-208), and then what it gives back is what this sets.
function setSkip(on, force = false) {
  if (on && vm.locked) return;
  vm.skipToggle = on;
  if (!on) vm.fastForwardHeld = false;
  $("mode-skip").classList.toggle("on", on);
  if (vm.instantModes) { Object.assign(vm.instantModes, { skip: on, force: on && force, paused: null }); return; }
  vm.skipPaused = null;
  vm.skip = on;
  vm.forceSkip = on && force;
  if (on) skipStarted();
}
// Skipping starting at the message on screen: it stops there at once if fast forward is on "Read" and the message has not been read (the flag is cleared before the
// frame step, 0x40ed0 at 0x418ec), and otherwise the wait ends.
function skipStarted() {
  if (vm.fastForwardRead && vm.msgPending && !vm.msgRead && (!vm.forceSkip || vm.fastForwardHeld)) { vm.pauseSkip(); return; }
  vm.advance(false);   // a timed wait goes on, at fast forward's speed (item 110)
}
// The fast-forward key (Ctrl, the pad's ZR). The game reads it every frame and leaves the toggle alone (0x40ed0 at 0x41840-0x418ac): it runs while the key is down unless the
// mode panel, a menu, the backlog, XSTP or a movie holds it back, and it is there again on the frame after that ends (N2-209). Letting go goes back to what the toggle says.
let ffKey = false;
function fastForwardKey(down) {
  if (down === ffKey) return;
  ffKey = down;
  if (!down && vm.fastForwardHeld) releaseFastForward();
}
function holdFastForward() {
  vm.fastForwardHeld = true;
  vm.skipPaused = null;
  vm.skip = true;
  vm.forceSkip = true;
  $("mode-skip").classList.add("on");
  skipStarted();
}
function releaseFastForward() {
  vm.fastForwardHeld = false;
  const toggle = vm.skipToggle;
  $("mode-skip").classList.toggle("on", toggle);
  if (vm.instantModes) { Object.assign(vm.instantModes, { skip: toggle, force: false, paused: null }); return; }
  if (vm.skipPaused) vm.skipPaused = toggle ? { force: false, held: false } : null;   // stopped at unread text: the toggle goes on waiting there
  else { vm.skip = toggle; vm.forceSkip = false; }
}
function syncFastForward() {
  if (vm.fastForwardHeld) { if (ui.panelOpen) releaseFastForward(); }
  else if (ffKey && vm.running && !vm.locked && !vm.instant && !ui.open && !ui.panelOpen && !moviesDone) holdFastForward();
  // with a screen up the key counts for nothing, so the indicator is the toggle's alone (0x40ed0 sets it from the toggle before anything else)
  $("mode-skip").classList.toggle("held-under", vm.fastForwardHeld && !vm.skipToggle && ui.open);
}
function setAuto(on) {
  if (on && vm.locked) return;
  if (on && !vm.auto) popup("auto");
  vm.auto = on;
  $("mode-auto").style.display = on ? "block" : "none";
  vm.armAuto();
}
function toggleAuto() {
  if (!vm.auto) setSkip(false);
  setAuto(!vm.auto);
}
function toggleSkip(force = false) {
  const on = !vm.skipToggle;
  if (on) setAuto(false);
  setSkip(on, force);
}

// ---- starting and saving --------------------------------------------------------------------------------------
// continueFlow: the story going on from the prologue, so the flowchart keeps the path that led here.
// Where a script that ends goes instead of the title: an episode played from the Ending List goes back to it.
let afterEnd = null, replayFrom = null;

// replay: a scene played from the gallery (its flowchart or the Ending List): IFSC knows it, and it makes no automatic
// save (0x47b10). The game starts those through ARCHIVE, which sets F024, F025 and F028 to 1 and F026 to the scene's
// jump number (G008) before jumping there; RTST then makes each scene current and its RDED ends the replay.
// vars: the story's variables to start with (a rewind from the flowchart keeps some).
async function startAt(i, label, { continueFlow = false, then = null, replay = false, jump = 0, vars = null, onFirstPicture = null } = {}) {
  afterEnd = then;
  audio.start();
  const keepMusic = vm.keepMusic;
  vm.keepMusic = false;
  vm.stop();
  vm.onFirstFade = onFirstPicture;
  audio.stopAll({ keepMusic });
  vm.replay = replay;
  vm.replaySource = replay ? replayFrom : null;   // a replay from the gallery's flowchart passes RDAS by (0x79b78, N2-2)
  vm.setLocked(false);
  vm.layers.clear();
  vm.pending.clear();
  vm.removed.clear();
  vm.clearAnimations();
  if (!continueFlow) vm.flow.resetPath();
  vm.vars = vars ? { ...vars } : {};
  // A scene entered directly sets up its own picture when this flag is on; in normal play it continues from the last.
  if (!vars && i !== vm.index.start) vm.vars.F026 = jump || 1;
  // ... and the story's own start sets F822 (the text window's layout), as ARCHIVE does before a scene played directly.
  if (!vars && i !== vm.index.start) vm.vars.F822 = 1;
  if (replay) Object.assign(vm.vars, { F024: 1, F025: 1, F028: 1 });
  text.clear();
  text.setOpen(false);
  text.pagePending = false;
  text.history = [];
  text.logged = 0;
  text.dropped = false;
  await vm.start(i, label);
}

// The title's movie: titlebg1-4 by how far the player has come (uifx.js), its opening once, then from 8 s on.
function titleVideo(on) {
  let v = $("movie");
  if (on) {
    const name = titleMovie();
    if (v.titleLoop && v.style.display === "block" && v.getAttribute("src") === movieUrl(name)) return;
    v = movieElement(name);
    v.titleLoop = true;
    v.muted = true;
    v.loop = false;
    v.onended = () => { if (v.titleLoop) { v.currentTime = TITLE_MOVIE_LOOP; v.play().catch(() => {}); } };
    v.style.display = "block";
    $("gl").style.visibility = "hidden";   // nothing of the story's canvas shows under the title's movie: one surface less for the browser to keep in step
    if (paintsMovies) paintMovie(v);
    v.play().catch(() => {});
  } else if (v.titleLoop) {
    v.titleLoop = false;
    v.onended = null;
    stopPaintingMovie(v);
    v.pause();
    v.muted = false;
    v.removeAttribute("src");
    v.load();
    v.style.display = "none";
    $("gl").style.visibility = "";
  }
}

// Config and Load opened from the title hold its movie on its frame, still drawn, and let it go on as they close (0x49630 -> 0x1b20).
function titleHold(on) {
  const v = $("movie");
  if (!v.titleLoop) return;
  if (on) v.pause(); else v.play().catch(() => {});
}

// The title's music (native 0x8e200): music 2, or 72 at the last title stage. Playing it again is no restart.
// Browsers hold sound until the first click or key; it starts then.
function titleMusic() {
  audio.start();
  audio.playBGM(titleTrack(ui.titleStageNow()), {});
}

// New Game (native 0x48ac0, 0x4945c): the story's own start, START_SCRIPT (jump 110), once the prologue (485) has
// started; before that the opening, 00_01 (jump 260), whose end leads to the first launch's title and its cautions.
// From the title, which ends at full white, the white is held until the first picture; at start-up (no title, the
// screen black, or the welcome page just faded to black) nothing is laid over the black canvas.
async function newGame({ fromTitle = true } = {}) {
  titleVideo(false);
  await startAt(vm.flow.started.has(485) ? vm.index.start : vm.index.names.indexOf("00_01"), undefined, { onFirstPicture: fromTitle ? holdWhite() : null });
}
// After the first launch's cautions (title state 0x14): the story starts, and this boot is no longer the first.
async function startStory() {
  firstLaunch = false;
  titleVideo(false);
  await startAt(vm.index.start, undefined, { onFirstPicture: holdWhite() });
}
// The title ends at full white and the story's first picture follows with no frame between (native frames: 255 throughout). The port fetches the
// script after the title has gone, and the canvas is black until the first FADS, so the white stays over it until that picture has been drawn.
function holdWhite() {
  const white = document.createElement("div");
  white.style.cssText = "position:absolute;inset:0;background:#fff";
  $("stage").insertBefore(white, $("ui"));
  return () => requestAnimationFrame(() => white.remove());
}

// A script that ends without jumping on goes back to the title (00_01 ends with RTMN, the music going on); on the first
// launch that title is "press any button" and the cautions, then the story. The story first fades to black at 0.02 a
// frame (0x48ac0 state 7). A replay goes back where it came from.
vm.onEnd = async () => {
  if (afterEnd) { const then = afterEnd; afterEnd = null; toTitle(false); then(); return; }
  preload.readyMovie(titleMovie(titleNext()));   // the title is next: its movie starts reading under the black
  await fadeToBlack(0.02);
  toTitle();
};

// The story going to black over everything but the interface (for the end of a script and Return to Title).
function fadeToBlack(rate) {
  return new Promise((res) => {
    let el = $("story-black");
    if (!el) { el = document.createElement("div"); el.id = "story-black"; $("popup").before(el); }
    let a = 0, first = true;
    el.style.opacity = "0";
    el.style.display = "block";
    // a step each game frame (vm.everyFrame), the first standing still
    vm.everyFrame(() => {
      a = Math.min(1, a + (first ? 0 : rate));
      first = false;
      el.style.opacity = String(a);
      if (a >= 1) { res(); return false; }
    });
  });
}

// Saved pages keep their text as plain characters: the per-letter spans are only for typing (and make a save several
// times larger than it needs to be).
function compactHtml(html) {
  const h = html || "";
  // the current line keeps its letters: a load types it again (0x5baf0 with param 2 = 0: the message runs again, N2-77)
  const lines = [...h.matchAll(/data-line="(\d+)"/g)];
  const last = lines.at(-1)?.[1];
  const cut = last === undefined ? h.length : lines.find((m) => m[1] === last).index;
  return h.slice(0, cut).replace(/<span class="ch on">([^<]{1,10})<\/span>/g, "$1") + h.slice(cut);
}

function thumbnail() {
  const c = document.createElement("canvas");
  c.width = 288; c.height = 162;
  gfx.present(vm.now(), false);   // the picture alone: the text window is not part of a save's picture
  c.getContext("2d").drawImage($("gl"), 0, 0, 288, 162);
  gfx.present(vm.now());
  return c.toDataURL("image/jpeg", 0.72);
}

// A save holds the checkpoint (native 0x527f0 -> 0xf17ff8; nothing can be saved before there is one, 0xf17ff2), with a
// picture of the screen as it is. Null when there is no checkpoint yet.
// quick: the quick save (0x52860) leaves the record's F1118 as it is; the manual and automatic ones mark it, so loading them
// does not ask "Save Progress?" again (0x50fc0 at 0x51554, 0x52aa0: 0x53f00(record + 8, 0x45e, 1), N2-37).
function makeSave({ quick = false } = {}) {
  const p = vm.savePoint;
  if (!p) return null;
  const s = { ...p, html: compactHtml(p.html), when: Date.now() };
  delete s.auto;
  if (!quick) s.vars = markSaved(p.vars);
  s.thumb = thumbnail();
  s.note = p.noteText ?? ((p.page || []).at(-1) || "");
  return s;
}
// Every save starts a 180-frame wait in which quick save is refused (0x40e70(0xb4)).
let saveCooldownUntil = 0;
function savedNow() { saveCooldownUntil = performance.now() + 3000; }

// Automatic saves (native 0x52aa0): the latest checkpoint goes to automatic slot 100, the others move down one, and
// the 39th is dropped (slots 100-138). Not when it is the same point as the newest one (0x52a20), nor in a gallery
// replay (0x47b10).
const AUTO = "tsuki.autosaves", AUTO_SLOTS = 39;
function autosaves() { try { return JSON.parse(localStorage.getItem(AUTO) || "[]"); } catch { return []; } }
function autosave() {
  const p = vm.savePoint;
  if (!p || vm.replay || !(vm.running || vm.restoring)) return false;
  const list = autosaves();
  if (list[0] && list[0].script === p.script && list[0].pc === p.pc && list[0].name === p.name) return false;
  const s = { ...p, html: compactHtml(p.html), auto: true, vars: markSaved(p.vars), when: Date.now() };
  s.thumb = thumbnail();
  s.note = p.noteText ?? ((p.page || []).at(-1) || "");
  list.unshift(s);
  list.length = Math.min(list.length, AUTO_SLOTS);
  for (let n = list.length; n > 0; n--) {
    try { localStorage.setItem(AUTO, JSON.stringify(list.slice(0, n))); popup("autosave"); return true; } catch { /* full: keep fewer */ }
  }
  return false;
}

function loadSave(s) {
  afterEnd = null;
  audio.start();
  stage.classList.remove("menu-blur", "notext");
  setSkip(false);
  vm.restore(s).catch((e) => toast(e.message, 4000));
}

// fromStory: the player chose Return to Title in the system menu, which writes the automatic save first. fade: the menu
// closes and the story fades to black at 0.02 a frame first (0x4cea0 case 4, 0x48ac0 state 7). leave(next): a screen open beside
// the column closes first (0x5912ec, state 9), after the save and its popup have started.
async function toTitle(showTitle = true, { fromStory = false, fade = false, leave = null } = {}) {
  const wrote = fromStory ? autosave() : false;
  if (fade && showTitle) preload.readyMovie(titleMovie(titleNext()));
  if (fade) {
    text.closeWindow();   // the text window goes from the press (0x4cea0: 0x2e120(0)), and its waiting mark with it
    onWait(false);
    if (leave) await new Promise((next) => leave(next));
    // With the automatic save written the menu fades at 1/30 a frame behind its popup, and the black waits for it to go, A or a
    // tap sending it on its way (0x4cea0 -> state 0x12: 0x4d710; a press calls 0x3b480, N2-31).
    if (wrote) await ui.waitForPopup(popupBusy, popupHurry);
    await ui.menuGone?.();
    text.noteOn = false;                          // state 0x15 clears F1110
    audio.stopAll({ keepMusic: vm.keepMusic });   // at the end of the menu's fall, before the black (state 0x15: 0x5f200, N2-32)
    ui.close(); vm.paused = true; await fadeToBlack(0.02);
  }
  afterEnd = null;
  const keepMusic = vm.keepMusic;
  vm.keepMusic = false;
  vm.stop();
  vm.setLocked(false);
  vm.replay = false;
  vm.clearAnimations();
  audio.stopAll({ keepMusic });
  vm.layers.clear();
  text.clear();
  text.setOpen(false);
  setSkip(false);
  setAuto(false);
  ui.close();
  if (showTitle) ui.title();
  const black = $("story-black");
  if (black) black.style.display = "none";
}

// The flowchart's jump to a scene (node: the chosen part). From the gallery it is a replay (0x11418 -> 0x5040, no
// question), which ends at the scene's RDED and comes back to the gallery's flowchart. In the story it is a rewind.
function flowchart(opts = {}) {
  return openFlowchart(ui, vm, (i, node) => {
    titleVideo(false); ui.close(); stage.classList.remove("notext"); setSkip(false); setAuto(false);
    if (opts.gallery) { replayFrom = "flowchart"; replayScene(node?.jump, () => galleryFlowchart(node?.flag)); }
    else rewindTo(i, node);
  }, null, opts);
}
// The game starts a replay from its flowchart through ARCHIVE (0x11418 -> 0x5040 keeps the part's jump; 0x48ac0 case 4 puts it in G008 and starts script 3000): that
// script and JUMP00 .. JUMPQA pick the scene and set what it reads, so the prologue's G008 260 reaches 00_02, not 00_01, and F050 / F054 show the hall scenes (N2-26, N2-27).
function replayScene(jump, then) {
  vm.setVar("G008", jump);
  startAt(vm.index.jump[3000], undefined, { replay: true, then });
}
// After a replay the gallery's flowchart starts on the scene played (0x7f38 passes its +0x38 to 0xf8fc).
function galleryFlowchart(select) {
  const env = galleryEnv();
  flowchart({ gallery: true, select, back: (o) => openGallery(ui, vm, env, undefined, o) });
}

// A rewind from the in-game flowchart (native 0x11a58 on Yes): the rows after the chosen one leave the path, the route
// flags set from the chosen row on are cleared (0x95800), and the story starts at the scene with what 0x178c8 records
// of its variables (the rest are reset by the game, 0x3c550; 0x17af0 puts these back): F1103 = 1, F110 (the current
// scene) = the node, F026 = its jump number, F823 / F847 and F1104-F1113 cleared; then the fixed fields, the low byte of
// each variable in the chart's keep list and its flags as 0 or 1.
function rewindTo(i, node) {
  const chart = vm.flowChart, v = { ...vm.vars };
  if (!node || !chart) { startAt(i); return; }
  vm.flow.rewindPath(chart, node.group);
  for (const [n, keepFrom] of ROUTE_FLAGS) if (node.group < keepFrom) v[fvar(n)] = 0;
  v.F1103 = 1; v.F823 = 0; v.F847 = 0;
  for (let n = 1104; n <= 1113; n++) v[fvar(n)] = 0;
  const kept = {};
  const has = (k) => v[k] !== undefined && v[k] !== 0;
  for (const n of REWIND_FIXED) if (has(fvar(n))) kept[fvar(n)] = v[fvar(n)];
  for (const n of chart.rewind?.keep || []) if (has(fvar(n))) kept[fvar(n)] = ((v[fvar(n)] & 0xff) << 24) >> 24;
  for (const n of chart.rewind?.flags || []) if (has(fvar(n))) kept[fvar(n)] = 1;
  kept.F026 = node.jump;
  vm.flow.current = node.flag;
  startAt(i, undefined, { continueFlow: true, vars: kept });
}

// The title's GALLERY: one screen with its own column (CG Gallery, Music Player, Flowchart, Movie, Ending List, Title).
// The title's music plays on in it (nothing in 0x4210 / 0x42d0 stops it); the gallery starts it again where the game
// does (gallery.js) and the Music Player cuts it while it is open.
function gallery(section, opts = {}) {
  preload.readyMovie(titleMovie(titleNext()));   // the gallery's Title goes back to it
  openGallery(ui, vm, galleryEnv(), section, opts);
}
function galleryEnv() {
  return {
    toast, titleVideo, titleMusic, flowchart, playMovie, endMovie: () => passMovie(),
    // An episode from the Ending List: played from its start, then back to the list.
    playEpisode: (e) => {
      ui.close(); stage.classList.remove("notext"); setSkip(false); setAuto(false);
      const i = vm.index.names.indexOf(e.script);
      const jump = Number(Object.keys(vm.index.jump).find((k) => vm.index.jump[k] === i)) || 0;
      replayFrom = "ending";
      startAt(i, e.label || undefined, { then: () => gallery("ending"), replay: true, jump });
    },
  };
}

const QUICK = "tsuki.quicksave";
let hasQuick = false;
try { hasQuick = !!localStorage.getItem(QUICK); } catch { /* none */ }

function rewind(toChoice) {
  if (vm.locked || !vm.canRewind(toChoice)) return;
  audio.start();
  setSkip(false);
  setAuto(false);
  stage.classList.remove("notext");
  backIcon(2, 1);   // lit for one frame: a rewind is done within the frame here
  vm.rewind(toChoice).catch((e) => toast(e.message, 4000));
}
const keys = new KeyMap();
const ui = new UI({
  vm, gfx, audio, text, keys,
  env: null,
});
ui.touch = touch.on ? touch : null;   // the screens ask it for their touch layouts
ui.env = {
  newGame, startStory, firstLaunch: () => firstLaunch, loadSave, makeSave, toTitle, flowchart, gallery, toast, settings, titleVideo, titleHold, titleMusic,
  setSetting, autosaves, preloadGallery,
  resetSettings: () => { settings = { ...DEFAULTS }; ui.env.settings = settings; for (const [k, v] of Object.entries(settings)) setSetting(k, v); audio.resetVolumes(); keys.reset(); },
  toggleAuto, toggleSkip, rewind,
  // the quick bar's own (ui.buildPanel): the log, hiding the text, full screen, and the system menu (row: opened on Save 0, Load 1 or Config 2)
  log: () => { if (vm.running && !vm.choosing) ui.backlog(); },
  hideText, fullscreen: toggleFullscreen, menu: (row = null) => { if (vm.running && !vm.locked) systemMenu(row); },
  quickRecord: () => { try { return JSON.parse(localStorage.getItem(QUICK) || "null"); } catch { return null; } },
  canPanel: () => (vm.running || vm.restoring) && (!ui.open || (ui.screen === "dialog" && ui.panelOpen)) && !moviesDone && !vm.locked,
  hasQuickSave: () => hasQuick,
  savedNow,
  // Quick save (native 0x4e170 result 9): the checkpoint to slot 139, refused (sound 2) without one or within 180
  // frames of the last save. Quick load (dialog 9, starting on No) shows the quick save's picture under the question
  // (0x89590 -> 0x4ae90), and is refused when slot 139 is empty. Neither in a gallery replay (0x4e0c0).
  quickSave: () => {
    const s = vm.replay || performance.now() < saveCooldownUntil ? null : makeSave({ quick: true });
    if (!s) { ui.sound(2); return; }
    try { localStorage.setItem(QUICK, JSON.stringify(s)); hasQuick = true; savedNow(); popup("quicksave"); } catch (e) { toast(e.message, 4000); }
  },
  quickLoad: () => {
    let s = null;
    try { s = JSON.parse(localStorage.getItem(QUICK) || "null"); } catch (e) { toast(e.message, 4000); return; }
    if (!s || vm.replay) { ui.sound(2); return; }
    ui.confirmSystem(vm.system?.messages?.["230"] || "Quick Load?", { startNo: true, picture: s.thumb }).then((yes) => { if (yes) loadSave(s); });
  },
  // A gallery replay's origin and its end from the menu's "End Scene Playback?" (dialog 12).
  replayFrom: () => (vm.replay ? replayFrom : null),
  endReplay: async (leave) => { const then = afterEnd; await toTitle(false, { fade: true, leave }); then?.(); },
  replayVoice: () => vm.replayVoice(),
  // The mode panel's "Jump to Next Scene" (0x40ed0 states 1-3): dialog 10, starting on No, then 20 frames and the
  // instant run (vm.beginInstant); "Return to Previous Scene" (states 4-6): dialog 11, starting on No, 20 frames, then
  // the checkpoint 0x81a50 picks (vm.previousScene).
  nextScene: async () => {
    if (!(await ui.confirmSystem(vm.system?.messages?.["232"] || "Jump to Next Scene?", { startNo: true }))) return;
    await countdown(20);
    if (!vm.choosing) vm.beginInstant();
  },
  previousScene: async () => {
    if (!(await ui.confirmSystem(vm.system?.messages?.["233"] || "Return to Previous Scene?", { startNo: true }))) return;
    await countdown(20, true);
    const p = vm.previousScene();
    if (!p) return;
    audio.start(); setSkip(false); setAuto(false); stage.classList.remove("notext");
    vm.restore(p, { rewind: true, restartMusic: true }).catch((e) => toast(e.message, 4000));   // 0x81a50 -> 0x5ef10
  },
  jumpBack: (seq, choice = false) => {
    audio.start(); setSkip(false); setAuto(false); stage.classList.remove("notext");
    return vm.jumpTo(seq, choice).catch((e) => { toast(e.message, 4000); return false; });
  },
};

// ---- input ----------------------------------------------------------------------------------------------------
// Mouse and keyboard first. The mouse: a click advances, a right click opens the system menu (or goes back), the wheel
// up opens the log and down advances, a middle click hides the text, and the top of the picture brings the quick bar
// down. The keys: one map for every screen (keys.js), shown and changed on the config's Controls page. A controller
// still works, through the same actions (below).
// Opening the system menu turns the skip toggle off for good (0x40ed0 at 0x42194-0x421ac clears bit 1 of 0xae0660, and closing the menu does not put it back; auto, bit 0,
// stays), so the >> goes and the text waits once the menu closes (N2-28).
function systemMenu(row = null) {
  setSkip(false);
  ui.system(row === null ? {} : { open: row });
}
const choosing = () => $("choices").style.display === "block";
// The text and its window out of the way, to look at the picture; any click or key brings them back.
function hideText() {
  if (!vm.running || ui.open || vm.locked) return;
  stage.classList.toggle("notext");
}
const showText = () => { const hidden = stage.classList.contains("notext"); stage.classList.remove("notext"); return hidden; };
// Full screen, with Esc kept for the menus where the browser allows it (it leaves full screen when held).
// The game is played full screen: any click or tap asks for it (below), until the Full screen key or the bar's FULL has taken the game
// out of it; the same key or button puts it back. Leaving it another way (the browser's own Esc) does not count: the next click returns.
let wantFull = true;
function toggleFullscreen() {
  if (document.fullscreenElement) { wantFull = false; document.exitFullscreen?.().catch(() => {}); return; }
  wantFull = true;
  const going = document.documentElement.requestFullscreen?.();
  if (!going) { toast("Full screen is not available here"); return; }
  going.then(() => navigator.keyboard?.lock?.(["Escape"])?.catch?.(() => {})).catch((e) => toast(e.message, 3000));
}
document.addEventListener("fullscreenchange", () => { if (!document.fullscreenElement) navigator.keyboard?.unlock?.(); });
// While the opening page is up (home.js) nothing asks for it: choosing a tab, following a link or scrolling is not playing. Starting the game
// from PLAY ONLINE asks, within that click or key (gameStarted, below), and from then on any click does, as above.
let fullHeld = homeDue(new URLSearchParams(location.search));
// ... and on a phone held upright it has a layout of its own, with no rotate screen: that asks for landscape only once the game has
// started (touch.js place and turned).
let homeUp = fullHeld;
if (touch.on) {
  touch.fullHeld = () => fullHeld;   // (the rotate screen's tap asks too, touch.js)
  touch.upright = () => homeUp;
  touch.reorient();
  fitStage();
}
function enterFullscreen() {
  if (!wantFull || document.fullscreenElement) return;
  try { document.documentElement.requestFullscreen?.()?.then(() => navigator.keyboard?.lock?.(["Escape"])?.catch?.(() => {}))?.catch(() => {}); } catch { /* not here */ }
}
addEventListener("click", () => { if (!fullHeld) enterFullscreen(); }, true);
const gameStarted = () => { fullHeld = false; enterFullscreen(); };

addEventListener("pointerdown", () => audio.start(), true);
stage.addEventListener("click", (e) => {
  audio.start();
  if (touch.storyClick(e)) return;   // touch: the tap that sent the control panel up, or one at the top strip, which brings it down
  if (ui.screen === "title" && ui.pressAny) return;
  if (ui.open) return;
  if (choosing()) return;
  if (moviesDone) { if (movieClicks) passMovie(); return; }
  if (showText()) return;
  vm.press();
});
// Any click, wherever it lands and whatever else it does, sends the quick bar up.
addEventListener("click", () => { ui.dismissPanel(); }, true);
stage.addEventListener("contextmenu", (e) => {
  e.preventDefault();
  if (ui.open) { ui.back(); return; }
  if (askingSkip()) { passMovie(); return; }
  if (ui.dismissPanel()) return;
  if (showText()) return;
  if (vm.running && !vm.locked && !moviesDone) systemMenu();   // the game's menu opens on a text wait, not over a movie
});
// The middle button hides the text (and must not start the browser's own scrolling).
stage.addEventListener("mousedown", (e) => { if (e.button === 1) e.preventDefault(); });
stage.addEventListener("auxclick", (e) => { if (e.button === 1) { e.preventDefault(); hideText(); } });
// During a choice the wheel moves its cursor (0x83e50), one row a notch (a trackpad's small steps add up to one).
// notch: the distance that counts as a turn; pause: the silence (ms) that ends a swipe; gap: the least time between two
// steps; after: how long the wheel is passed over once a screen has closed under it.
const WHEEL = { notch: 50, pause: 200, gap: 150, after: 400 };
let choiceWheelSum = 0, wheelSum = 0, wheelAt = -Infinity, wheelUsed = false, wheelStepAt = -Infinity, wheelHold = -Infinity;
stage.addEventListener("wheel", (e) => {
  if (ui.choiceWheel && choosing()) {
    choiceWheelSum += e.deltaY;
    if (Math.abs(choiceWheelSum) >= 50) { ui.choiceWheel(choiceWheelSum); choiceWheelSum = 0; }
    return;
  }
  // (a turn that began over a screen, the log scrolled past its end say, does not carry on into the story)
  if (ui.open || !vm.running || vm.locked) { wheelAt = e.timeStamp; wheelUsed = true; wheelHold = e.timeStamp + WHEEL.after; return; }
  if (e.timeStamp < wheelHold) { wheelAt = e.timeStamp; return; }
  // One turn is one step. A wheel's notch is a step by itself; a trackpad's stream of small moves adds up to one, and the
  // rest of that swipe (its coasting too, and the tail of a swipe that began in a screen now closed) is passed over
  // until the stream has paused.
  const flowing = e.timeStamp - wheelAt < WHEEL.pause;
  wheelAt = e.timeStamp;
  if (!flowing) { wheelSum = 0; wheelUsed = false; }
  if (wheelUsed && (flowing && Math.abs(e.deltaY) < WHEEL.notch)) return;
  if (Math.sign(e.deltaY) !== Math.sign(wheelSum)) wheelSum = 0;
  wheelSum += e.deltaMode === 0 ? e.deltaY : e.deltaY * WHEEL.notch;
  if (Math.abs(wheelSum) < WHEEL.notch || e.timeStamp - wheelStepAt < WHEEL.gap) return;
  wheelStepAt = e.timeStamp;
  const up = wheelSum < 0;
  wheelSum = 0;
  wheelUsed = true;
  if (up) ui.backlog();
  else if (!moviesDone && !showText()) vm.press();
}, { passive: true });

// The quick bar comes down when the mouse reaches the top of the picture. The pointer goes out of sight when it has
// rested for a while over the story, and comes back as it moves.
let idleTimer = null;
addEventListener("mousemove", (e) => {
  if (touch.on) return;   // a tap's own mouse events are not a mouse at the top of the picture
  stage.classList.remove("idle");
  clearTimeout(idleTimer);
  idleTimer = setTimeout(() => { if (vm.running && !ui.open && !ui.panelOpen && !choosing()) stage.classList.add("idle"); }, 3000);
  if (e.buttons) return;
  const r = stage.getBoundingClientRect(), y = (e.clientY - r.top) * 1080 / r.height;
  if (y >= 0 && y < QUICK_BAR.zone && e.clientX >= r.left && e.clientX < r.right) ui.openPanel();
  else ui.panelHold = false;   // away from the top: the bar may come down again
});

// What a key or a pad button does on the story screen. e: the event, for its repeat.
function runAction(act, e = {}) {
  if (vm.locked) return false;
  switch (act) {
    case "advance":
      // a press acts once: advance reads the press edge (0x81b30 / 0x802c0, input +0x10), a held key does not repeat it (N2-82)
      if (e.repeat || choosing()) return true;
      if (moviesDone) passMovie(); else if (!showText()) vm.press();
      return true;
    case "menu":
      if (askingSkip()) passMovie(); else if (!moviesDone && !showText() && vm.running) systemMenu();
      return true;
    case "save": case "load": case "config":
      if (vm.running && !moviesDone) systemMenu(["save", "load", "config"].indexOf(act));
      return true;
    case "skip": if (!choosing()) toggleSkip(); return true;
    case "auto": toggleAuto(); return true;
    case "rewind": if (vm.running) rewind(false); return true;
    case "log": if (vm.running && !choosing() && !moviesDone) ui.backlog(); return true;
    case "bar": if (vm.running && !choosing()) ui.modePanel(); return true;
    case "hide": hideText(); return true;
    case "voice": vm.replayVoice(); return true;
    case "quickSave": if (vm.running && !moviesDone && !e.repeat) ui.env.quickSave(); return true;
    case "quickLoad": if (vm.running && !moviesDone && !e.repeat) ui.env.quickLoad(); return true;
    case "prevScene": if (vm.running && !moviesDone && !e.repeat && vm.previousScene(false)) ui.env.previousScene(); return true;
    case "nextScene":
      if (vm.running && !moviesDone && !e.repeat && !choosing() && !vm.instant && !(vm.replay && vm.replaySource === "flowchart")) ui.env.nextScene();
      return true;
    default: return false;
  }
}
// The key held for fast forward is read whatever else is held with it.
const isFastKey = (e) => keys.byKey.get(keyName(e)) === "fast";
addEventListener("keydown", (e) => {
  audio.start();
  if (isFastKey(e)) fastForwardKey(true);
  if (ui.open) return;   // a screen has the keys (ui.key)
  const act = keys.action(e);
  if (act === "fullscreen") { if (!e.repeat) toggleFullscreen(); e.preventDefault(); return; }
  if (vm.locked && !(e.key === "F5" || e.key === "F11" || e.key === "F12")) { e.preventDefault(); return; }
  if (ui.panelKey(e)) { e.preventDefault(); return; }
  if (act === "fast") { e.preventDefault(); return; }   // read every frame (syncFastForward)
  if (act && runAction(act, e)) e.preventDefault();
});
addEventListener("keyup", (e) => { if (isFastKey(e)) fastForwardKey(false); });
addEventListener("blur", () => fastForwardKey(false));   // a key let go in another window never reports it

// ---- controllers ----------------------------------------------------------------------------------------------
// A controller is a second way to play, as the game's own Controls page had it: A confirm and advance, B cancel or stop
// skipping, Y system menu, X log, up the quick bar, down advance, R skip, L auto, ZR fast forward while held, ZL rewind.
// The Gamepad API's standard layout numbers the face buttons by position (0 bottom = B, 1 right = A, 2 left = Y, 3 top = X
// on a Nintendo layout). On the story screen a button runs its action; in the menus it is the menus' key; held
// directions repeat.
const PAD = { 1: "A", 0: "B", 2: "Y", 3: "X", 12: "Up", 13: "Down", 14: "Left", 15: "Right", 5: "R", 4: "L", 9: "Y", 6: "ZL", 7: "ZR" };
const PAD_MENU = { A: "Enter", B: "Escape", Up: "ArrowUp", Down: "ArrowDown", Left: "ArrowLeft", Right: "ArrowRight", L: "Tab", R: "Tab" };
const PAD_STORY = { A: "advance", Down: "advance", Y: "menu", X: "log", Up: "bar", R: "skip", L: "auto", ZL: "rewind" };
const padHeld = new Map();
// repeat: a held direction's repeat (KeyboardEvent.repeat), which choices and dialogs treat differently from a press.
function padKey(btn, down = true, repeat = false) {
  if (btn === "ZR") { fastForwardKey(down); return; }
  if (!down) return;
  if (ui.open || choosing() || (ui.panelOpen && ui.panel.keyboard)) {
    const key = PAD_MENU[btn];
    if (key) dispatchEvent(new KeyboardEvent("keydown", { key, shiftKey: btn === "L", repeat, bubbles: true, cancelable: true }));
    return;
  }
  if (btn === "B") { if (askingSkip()) passMovie(); else if (vm.skipOn) setSkip(false); return; }
  if (PAD_STORY[btn]) runAction(PAD_STORY[btn], { repeat });
}
// In the menus (a screen, the quick bar or a choice up) the right stick goes with the D-pad: their direction masks
// (0x100010 up, 0x400040 down, 0x800080 left, 0x200020 right) take the second stick's directions, set past 80 of 128
// (0xb3a18), and the PC build feeds that stick from the pad's right stick, past its dead zone of 7849 / 32767. The left
// stick is the first, which scrolls (flowchart.js stickY). Directions pulse as the input's repeat does: at the push,
// after 15 frames, then every 5 (0xb3a18 with +0x3ec / +0x3e8).
const STICK_DEAD_ZONE = 7849 / 32767, STICK_DIR = 80 / 128;
function pollGamepads(now) {
  const pads = navigator.getGamepads ? navigator.getGamepads() : [];
  const pressed = new Set();
  const menus = ui.open || ui.panelOpen || choosing();
  for (const pad of pads) {
    if (!pad || pad.mapping !== "standard") continue;
    pad.buttons.forEach((b, i) => { if (b.pressed && PAD[i]) pressed.add(i); });
    if (!menus) continue;
    const ax = (k) => { const v = pad.axes?.[k] ?? 0; return Math.abs(v) < STICK_DEAD_ZONE ? 0 : v; };
    if (ax(3) < -STICK_DIR) pressed.add(12);
    if (ax(3) > STICK_DIR) pressed.add(13);
    if (ax(2) < -STICK_DIR) pressed.add(14);
    if (ax(2) > STICK_DIR) pressed.add(15);
  }
  for (const i of pressed) {
    const h = padHeld.get(i);
    const dir = i >= 12 && i <= 15;
    if (!h) { padHeld.set(i, { next: now + (dir ? 250 : 400) }); audio.start(); padKey(PAD[i]); }
    else if (dir || i === 6) { if (now >= h.next) { h.next = now + (i === 6 ? 250 : 1000 / 12); padKey(PAD[i], true, true); } }
  }
  for (const i of [...padHeld.keys()]) if (!pressed.has(i)) { padHeld.delete(i); padKey(PAD[i], false); }
}

// What a finger does on the story's screen goes through the same actions (touch.js).
touch.bind({ ui, vm, audio, act: { fast: fastForwardKey, log: () => ui.backlog(), hide: hideText, choosing, movie: () => !!moviesDone, refit: fitStage } });

// After START on the first page: the game's own "Loading" window, with how far along it is, until what the next screen and the story's first
// screen use has been read (preload.js: the start-up list's first two ranks, which have the first voices, sounds and pictures) and the movie
// that comes first can start. It is not shown at all when that is so already (the page was read for a while), stays at least `least` ms so
// that it does not flash, gives the movie `movie` ms, and goes on regardless after `most`: what has not come is read when it is wanted.
const LOADING = { least: 700, movie: 6000, most: 20000, out: 300 };
async function loadingScreen() {
  const ready = (t) => preload.settled(RANK.story) && (preload.moviesReady() || t > LOADING.movie);
  if (ready(0)) return;
  const word = vm.system?.messages?.["184"] || "Loading", since = performance.now();
  const note = ui.notify(word, { held: true, live: () => `${word}  ${Math.floor(preload.progress(RANK.story) * 100)}%` });
  await new Promise((done) => {
    const look = () => {
      const t = performance.now() - since;
      if ((t >= LOADING.least && ready(t)) || t >= LOADING.most) done(); else setTimeout(look, 100);
    };
    look();
  });
  note.close();
  await new Promise((done) => setTimeout(done, LOADING.out));   // the window's own way out (0.07 a frame)
}

// ---- start ----------------------------------------------------------------------------------------------------
(async () => {
  await vm.init();
  if (vm.flow.started.has(485)) firstLaunch = false;   // 0xb5f30, however the page was opened
  setSetting("textSpeed", settings.textSpeed);
  window.vm = vm;
  window.gfx = gfx;
  window.gameText = text;
  text.pageCounter = () => [vm.getVar("F822"), vm.getVar("F823")];
  window.ui = ui;
  window.keys = keys;
  requestAnimationFrame(frame);
  // Letters drawn on a canvas (the plates, the config's words, the Audio Track label) take whatever face is ready when they are drawn and are not
  // drawn again: where the system has none of a stack's fonts, its bundled backup (style.css) is fetched first. A system that has them asks for
  // nothing; 3 s at most, then the canvases draw with what there is.
  const wanted = CANVAS_FONTS.filter((f) => !f.system.some(installedFont)).map((f) => f.backup);
  await Promise.race([Promise.all(wanted.map((f) => document.fonts?.load?.(f)?.catch(() => {}))), new Promise((r) => setTimeout(r, 3000))]);
  // The quick bar's art is made here, on the black before the first screen, so that its first opening looks like every other.
  ui.buildPanel();
  relettered().then((art) => { ui.confArt = art; });   // the System page's words at one size (confart.js), ready before the config is first opened
  await ui.panel.ready;
  const q = new URLSearchParams(location.search);
  const firstVisit = welcomeDue(q);   // (marked as made once the first screens have loaded, below)
  if (q.has("mute")) audio.muted = true;   // for testing: no sound at all
  // From here on, while the first page is read (or the logo plays), what comes after it is fetched, the most pressing first: the opening or the title, the
  // story's screen, the menus, the gallery.
  preload.startup({ firstLaunch, stage: firstLaunch ? 0 : titleNext(), scene: q.has("script") });
  window.preload = preload;
  // The opening page (home.js): About, GitHub, the downloads, and PLAY ONLINE, whose press is the click the browser wants before it will play sound.
  if (homeDue(q)) await openHome(ui, { started: gameStarted });
  homeUp = false;
  touch.reorient?.();   // the game's own stage again, and in portrait the rotate screen
  fitStage();
  if (firstVisit) { await loadingScreen(); markWelcomed(); }   // ... and what the first screens use is waited for, under the game's "Loading"
  if (q.has("script")) {
    const name = q.get("script");
    const i = Number.isNaN(Number(name)) ? vm.index.names.indexOf(name) : Number(name);
    // ?pc=N (for testing): fast-forward to that command of the script, then play normally
    const until = q.has("pc") ? Number(q.get("pc")) : 0;
    if (until) {
      vm.skip = true;
      vm.forceSkip = true;
      vm.skipUntil = until;
    }
    await startAt(i, q.get("label") || undefined);
  } else if (q.has("resume") && ui.newestRecord()) {
    // ?resume: straight to the newest record, as Continue loads it. The iOS app (web-dev/ios) opens the page this way
    // when the system has ended it under the player (no logo, no title: the story as it was at the last save).
    loadSave(ui.newestRecord());
  } else if (await boot()) ui.title();
  else await newGame({ fromTitle: false });
})().catch((e) => {
  console.error(e);
  toast("Could not start: " + e.message, 10000);
});
