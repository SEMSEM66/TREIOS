// bridge.js - what the iOS app (web-dev/ios) adds to the page, run before any of the page's own code. Nothing in
// web/app knows of it: the page is the one the website and the Android app serve. It carries the page's console
// and errors to the app's debug log (no Safari Web Inspector without a Mac), mirrors localStorage to a file,
// passes a movie that cannot play instead of leaving the game waiting on it, and keeps the sound going past the
// ring/silent switch.
(() => {
  "use strict";
  if (window.__tsukiBridge) return;
  const N = window.__tsukiNative || {};
  const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.tsuki;
  const post = (m) => { try { if (handler) handler.postMessage(m); } catch { /* not in the app */ } };

  // ---- the console and uncaught errors, to the debug log -------------------------------------------------------
  const show = (v) => {
    if (typeof v === "string") return v;
    if (v instanceof Error) return `${v.name}: ${v.message}${v.stack ? "\n" + v.stack : ""}`;
    try { const s = JSON.stringify(v); return s === undefined ? String(v) : s; } catch { return String(v); }
  };
  const line = (args) => { const s = Array.prototype.map.call(args, show).join(" "); return s.length > 4000 ? s.slice(0, 4000) + " ..." : s; };
  const log = (level, msg) => post({ t: "log", level, msg });
  for (const level of ["log", "info", "warn", "error", "debug"]) {
    const was = console[level];
    console[level] = function (...args) {
      try { log(level, line(args)); } catch { /* the log must never break the page */ }
      return was.apply(console, args);
    };
  }
  addEventListener("error", (e) => {
    if (e.synthetic) return;
    const el = e.target;
    if (el && el !== window && el.tagName) {   // a file that would not load, or a movie that would not play
      const media = el.error ? ` (media error ${el.error.code}${el.error.message ? ": " + el.error.message : ""})` : "";
      log("error", `could not load <${el.tagName.toLowerCase()}> ${el.currentSrc || el.getAttribute("src") || el.getAttribute("href") || ""}${media}`);
    } else {
      log("error", `uncaught: ${e.message} at ${e.filename}:${e.lineno}:${e.colno}${e.error && e.error.stack ? "\n" + e.error.stack : ""}`);
    }
  }, true);
  addEventListener("unhandledrejection", (e) => log("error", `unhandled rejection: ${show(e.reason)}`));

  // ---- the saves, mirrored to a file ---------------------------------------------------------------------------
  // Every change to localStorage is told to the app, which keeps Documents/Saves/localStorage.json. A page that
  // starts with nothing stored takes the mirror back before the game reads its saves.
  try {
    const store = window.localStorage, proto = Storage.prototype;
    const mine = (k) => String(k).startsWith("tsuki.");   // every key of the game's (the probe page's test keys are not saves)
    const stored = () => { const keys = []; for (let i = 0; i < store.length; i++) { const k = store.key(i); if (mine(k)) keys.push(k); } return keys; };
    const mirror = N.saveMirror;
    delete N.saveMirror;
    if (N.mode === "game") {
      const keys = stored();
      if (mirror && keys.length === 0) {
        let count = 0;
        for (const k of Object.keys(mirror)) { try { store.setItem(k, mirror[k]); count++; } catch { /* over the quota: the rest stays in the file */ } }
        post({ t: "saves", op: "restored", count });
      } else if (keys.length && !N.hasSaveMirror) {
        const items = {};
        for (const k of keys) items[k] = store.getItem(k);
        post({ t: "saves", op: "snapshot", items });
      }
      const set = proto.setItem, remove = proto.removeItem, clear = proto.clear;
      proto.setItem = function (k, v) { set.call(this, k, v); if (this === store && mine(k)) post({ t: "saves", op: "set", k: String(k), v: String(v) }); };
      proto.removeItem = function (k) { remove.call(this, k); if (this === store && mine(k)) post({ t: "saves", op: "remove", k: String(k) }); };
      proto.clear = function () { clear.call(this); if (this === store) post({ t: "saves", op: "clear" }); };
    }
  } catch (e) { log("error", `save mirror: ${show(e)}`); }

  // ---- sound ---------------------------------------------------------------------------------------------------
  // Web Audio alone counts as "ambient" sound to iOS, which the ring/silent switch mutes; a game's sound is playback.
  try { if (navigator.audioSession) navigator.audioSession.type = "playback"; } catch { /* an older WebKit */ }
  // After a call, an alarm or Siri the audio context is left "interrupted": the app asks for it back.
  const resumeAudio = () => {
    const audio = window.vm && window.vm.audio, ctx = audio && audio.ctx;
    if (!ctx) return "no context";
    const was = ctx.state;
    if (was !== "running" && was !== "closed" && !document.hidden && !audio.muted) ctx.resume().catch(() => {});
    return was;
  };

  // ---- what this iPhone can decode, asked once as the game starts ------------------------------------------------------
  if (N.mode === "game") {
    // AV1, which every movie of the game is. (canPlayType says "probably" even where there is no decoder; this does not.)
    // The app is told, and where a set of fallback movies is installed it serves those under the same addresses.
    try {
      navigator.mediaCapabilities.decodingInfo({ type: "file", video: { contentType: 'video/mp4; codecs="av01.0.08M.08"', width: 1920, height: 1080, bitrate: 5000000, framerate: 30 } })
        .then((c) => {
          post({ t: "caps", av1: !!c.supported });
          log("info", `movies: AV1 supported ${c.supported}, smooth ${c.smooth}, power efficient ${c.powerEfficient}${c.supported ? "" : " (the movies will be passed over unless fallback movies are installed)"}`);
        }, (e) => log("warn", `movies: could not ask about AV1: ${show(e)}`));
    } catch (e) { log("warn", `movies: could not ask about AV1: ${show(e)}`); }
    // Ogg Opus, which every voice, song and sound is. Without it the game is silent: the app says so.
    fetch("/__native/media/opus.ogg").then((r) => (r.ok ? r.arrayBuffer() : null)).then((data) => {
      if (!data) return;   // a build without the probe's clips
      const Offline = window.OfflineAudioContext || window.webkitOfflineAudioContext;
      return new Offline(2, 1, 48000).decodeAudioData(data).then(
        (buf) => log("info", `sound: Ogg Opus decodes (${buf.duration.toFixed(2)} s, ${buf.sampleRate} Hz)`),
        (e) => { log("error", `sound: Ogg Opus does NOT decode on this iOS: ${show(e)}`); post({ t: "action", name: "no-opus" }); });
    }).catch((e) => log("warn", `sound: the Ogg Opus check could not run: ${show(e)}`));
  }

  // ---- movies --------------------------------------------------------------------------------------------------
  // A movie the phone cannot decode gives an error, and the game passes it by itself (main.js playMovie). One that
  // neither plays nor fails would hold the story for ever: after STALL seconds without a new frame it is given the
  // error it should have had. Both are logged, so the log tells which movies did not play.
  const STALL = 8;
  const title = (v) => (v.currentSrc || v.getAttribute("src") || "").split("/").pop() || "(no file)";
  const watched = new WeakMap();
  const unwatch = (v) => { const w = watched.get(v); if (w) { clearInterval(w.timer); watched.delete(v); } };
  const watch = (v) => {
    unwatch(v);
    const w = { at: v.currentTime, since: performance.now(), timer: 0 };
    w.timer = setInterval(() => {
      const now = performance.now();
      if (!v.isConnected || !v.getAttribute("src") || v.ended) { unwatch(v); return; }
      if (v.paused || document.hidden || v.currentTime !== w.at) { w.at = v.currentTime; w.since = now; return; }
      if (now - w.since < STALL * 1000) return;
      unwatch(v);
      log("warn", `movie ${title(v)}: no new frame for ${STALL} s (readyState ${v.readyState}, networkState ${v.networkState}, at ${v.currentTime.toFixed(2)} s): passing it`);
      const e = new Event("error");
      e.synthetic = true;
      v.dispatchEvent(e);
    }, 1000);
    watched.set(v, w);
  };
  const onVideo = (type, fn) => document.addEventListener(type, (e) => { const v = e.target; if (v && v.tagName === "VIDEO") fn(v, e); }, true);
  onVideo("play", (v) => watch(v));
  onVideo("playing", (v) => { if (!v.__logged) { v.__logged = v.currentSrc; log("info", `movie ${title(v)}: playing, ${v.videoWidth}x${v.videoHeight}, ${isFinite(v.duration) ? v.duration.toFixed(2) : "?"} s${v.muted ? ", muted" : ""}`); } });
  onVideo("emptied", (v) => { v.__logged = null; unwatch(v); });
  onVideo("ended", (v) => unwatch(v));
  onVideo("error", (v, e) => { if (!e.synthetic) unwatch(v); });
  // A movie read ahead (preload.js) fails before it is in the page, where no listener of the page's sees it; the game
  // then finds out when it asks it to play. That refusal is logged here (the game passes the movie on its own).
  try {
    const play = HTMLMediaElement.prototype.play;
    HTMLMediaElement.prototype.play = function () {
      const p = play.apply(this, arguments);
      if (this.tagName === "VIDEO" && p && p.catch) p.catch((e) => log("warn", `movie ${title(this)}: play() refused: ${e && e.name ? `${e.name}: ${e.message}` : e}${this.error ? ` (media error ${this.error.code})` : ""}`));
      return p;
    };
  } catch (e) { log("error", `movie log: ${show(e)}`); }

  // ---- the page, once, for the log -------------------------------------------------------------------------------
  addEventListener("load", () => {
    let insets = "";
    try {
      const probe = document.createElement("div");
      probe.style.cssText = "position:fixed;visibility:hidden;padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left)";
      document.documentElement.append(probe);
      const cs = getComputedStyle(probe);
      insets = [cs.paddingTop, cs.paddingRight, cs.paddingBottom, cs.paddingLeft].join(" ");
      probe.remove();
    } catch { /* unknown */ }
    log("info", `page ${location.href}: secure context ${window.isSecureContext}, window ${innerWidth}x${innerHeight} @${devicePixelRatio}, safe area ${insets}, ` +
      `touch-first ${matchMedia("(hover: none) and (pointer: coarse)").matches}, fullscreen API ${!!document.documentElement.requestFullscreen}, ` +
      `audioSession ${navigator.audioSession ? navigator.audioSession.type : "none"}, stored keys ${localStorage.length}, ${navigator.userAgent}`);
  });

  // ---- the safe area ----------------------------------------------------------------------------------------------
  // The page lays the stage out inside env(safe-area-inset-*) (touch.js), reading them when the window changes size.
  // In the app they reach the page a moment after it has loaded, and with no change of size: when they change, the
  // page is told as if the window had, and the stage is fitted again.
  const safeArea = () => {
    try {
      let el = document.getElementById("tsuki-native-safe");
      if (!el) {
        if (!document.documentElement) return null;
        el = document.createElement("div");
        el.id = "tsuki-native-safe";
        el.style.cssText = "position:fixed;left:0;top:0;width:0;height:0;visibility:hidden;pointer-events:none;padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left)";
        document.documentElement.append(el);
      }
      const cs = getComputedStyle(el);
      return [cs.paddingTop, cs.paddingRight, cs.paddingBottom, cs.paddingLeft].join(" ");
    } catch { return null; }
  };
  let insetsWere = null;
  setInterval(() => {
    const now = safeArea();
    if (now === null || now === insetsWere) return;
    if (insetsWere !== null) {
      log("info", `safe area (top right bottom left) now ${now}, was ${insetsWere}; window ${innerWidth}x${innerHeight}`);
      window.dispatchEvent(new Event("resize"));
    }
    insetsWere = now;
  }, 500);

  // ---- how smoothly it runs, for the log (debug builds): frames a second, and the longest wait between two ------------
  if (N.debug && N.mode === "game") {
    let frames = 0, longest = 0, last = 0, since = performance.now();
    const tick = (t) => {
      if (last) longest = Math.max(longest, t - last);
      last = t;
      frames++;
      requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
    setInterval(() => {
      const now = performance.now(), span = (now - since) / 1000;
      if (!document.hidden && span > 0) {
        const vm = window.vm, movie = document.getElementById("movie");
        log("info", `perf: ${(frames / span).toFixed(1)} frames a second over ${span.toFixed(0)} s, longest frame ${longest.toFixed(0)} ms; script ${vm && vm.script ? vm.script.name : "-"}, pc ${vm ? vm.pc : "-"}, ` +
          `movie ${movie && movie.style.display === "block" ? `on screen (${title(movie)} at ${movie.currentTime.toFixed(1)} s)` : "none"}`);
      }
      frames = 0; longest = 0; last = 0; since = now;
    }, N.ci ? 15000 : 60000);
  }

  // ---- CI only (-TsukiAutopilot 1): Enter every so often, so a simulator run moves through the story by itself ----
  if (N.autopilot) {
    let n = 0;
    setInterval(() => {
      if (document.hidden || !document.body) return;
      for (const type of ["keydown", "keyup"]) document.body.dispatchEvent(new KeyboardEvent(type, { key: "Enter", code: "Enter", bubbles: true, cancelable: true }));
      if (++n % 4 === 0) {
        const vm = window.vm, ctx = vm && vm.audio && vm.audio.ctx;
        log("info", `autopilot: script ${vm && vm.script ? vm.script.name : "-"}, pc ${vm ? vm.pc : "-"}, running ${vm ? vm.running : "-"}, audio ${ctx ? ctx.state : "none"}`);
      }
    }, 1500);
  }

  window.__tsukiBridge = { resumeAudio, post, log };
})();
