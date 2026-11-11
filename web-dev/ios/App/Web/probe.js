// probe.js - the compat probe of the iOS app (web-dev/ios): what this iPhone's WebKit does with everything the game
// asks of a browser, measured here and not looked up. The page is served like the game (app://tsukihime.ios/), so
// the file serving is measured too. The results go on screen, to the debug log, and to Documents/Logs/probe-result.json.
(() => {
  "use strict";
  const MEDIA = "/__native/media/";
  const N = window.__tsukiNative || {};
  const post = (m) => { try { window.webkit.messageHandlers.tsuki.postMessage(m); } catch { /* not in the app */ } };
  const $ = (id) => document.getElementById(id);
  let results = [];

  const add = (group, name, ok, detail) => {
    const state = ok === true ? "ok" : ok === false ? "fail" : "info";
    results.push({ group, name, state, detail: String(detail) });
    const tr = document.createElement("tr");
    for (const [cls, text] of [["g", group], ["n", name], [`s ${state}`, state === "fail" ? "FAIL" : state], ["d", String(detail)]]) {
      const td = document.createElement("td");
      td.className = cls;
      td.textContent = text;
      tr.append(td);
    }
    $("rows").append(tr);
    console.info(`probe [${state === "fail" ? "FAIL" : state}] ${group} / ${name}: ${detail}`);
  };
  const within = (p, ms, what) => Promise.race([p, new Promise((_, no) => setTimeout(() => no(new Error(`nothing after ${ms} ms${what ? " (" + what + ")" : ""}`)), ms))]);
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const says = (e) => (e && e.name ? `${e.name}: ${e.message}` : String(e));
  // fn returns a detail (passed), or [ok, detail] with ok true, false or null (information only); a throw is a fail.
  const test = async (group, name, fn) => {
    try {
      const r = await fn();
      if (Array.isArray(r)) add(group, name, r[0], r[1]); else add(group, name, true, r);
    } catch (e) { add(group, name, false, says(e)); }
  };
  const bytes = async (url) => {
    const r = await fetch(url);
    if (!r.ok) throw new Error(`${url}: ${r.status}`);
    return r.arrayBuffer();
  };
  const state = (group, name) => (results.find((r) => r.group === group && r.name === name) || {}).state;

  // ---- the device and the page ----------------------------------------------------------------------------------
  async function environment() {
    const d = N.device || {};
    add("Device", "iOS", null, `${d.system || "?"} (${d.systemBuild || "?"})`);
    add("Device", "model", null, `${d.modelName || "?"} [${d.model || "?"}], chip ${d.chip || "?"}, ${d.cores || "?"} cores, ${d.physicalMemoryMB || "?"} MB RAM${d.simulator ? ", SIMULATOR" : ""}`);
    add("Device", "hardware decoders", null, `AV1 ${d.hardwareDecodeAV1}, HEVC ${d.hardwareDecodeHEVC}, H.264 ${d.hardwareDecodeH264} (VideoToolbox)`);
    add("Device", "app", null, `${d.app || "?"}, commit ${d.commit || "?"}, free disk ${d.freeDiskMB || "?"} MB, low power mode ${d.lowPowerMode}`);
    add("Page", "user agent", null, navigator.userAgent);
    let insets = "?";
    try {
      const el = document.createElement("div");
      el.style.cssText = "position:fixed;visibility:hidden;padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left)";
      document.body.append(el);
      const cs = getComputedStyle(el);
      insets = [cs.paddingTop, cs.paddingRight, cs.paddingBottom, cs.paddingLeft].join(" ");
      el.remove();
    } catch { /* unknown */ }
    add("Page", "window", null, `${innerWidth}x${innerHeight} @${devicePixelRatio}, screen ${screen.width}x${screen.height}, safe area (top right bottom left) ${insets}`);
    await test("Page", "address", () => [window.isSecureContext === true, `${location.origin}, secure context ${window.isSecureContext}`]);
    await test("Page", "touch-first", () => {
      const q = matchMedia("(hover: none) and (pointer: coarse)").matches;
      return [N.device && N.device.simulator ? null : q, `(hover: none) and (pointer: coarse) ${q}, maxTouchPoints ${navigator.maxTouchPoints}`];
    });
    await test("Page", "needed APIs", () => {
      const need = { structuredClone: typeof structuredClone === "function", createImageBitmap: typeof createImageBitmap === "function",
        AudioContext: !!(window.AudioContext || window.webkitAudioContext), OfflineAudioContext: !!(window.OfflineAudioContext || window.webkitOfflineAudioContext),
        WebGL2: typeof WebGL2RenderingContext !== "undefined", "document.fonts": !!document.fonts, PointerEvent: typeof PointerEvent !== "undefined",
        visualViewport: !!window.visualViewport, "ES modules": "noModule" in HTMLScriptElement.prototype, "CSS.supports": !!(window.CSS && CSS.supports) };
      const gone = Object.keys(need).filter((k) => !need[k]);
      return [gone.length === 0, gone.length ? `missing: ${gone.join(", ")}` : `all there: ${Object.keys(need).join(", ")}`];
    });
    await test("Page", "optional APIs", () => {
      const have = { "Fullscreen API": !!document.documentElement.requestFullscreen, "orientation.lock": !!(screen.orientation && screen.orientation.lock),
        wakeLock: !!navigator.wakeLock, audioSession: !!navigator.audioSession, getGamepads: !!navigator.getGamepads,
        requestVideoFrameCallback: "requestVideoFrameCallback" in HTMLVideoElement.prototype, "keyboard.lock": !!(navigator.keyboard && navigator.keyboard.lock),
        mediaCapabilities: !!navigator.mediaCapabilities };
      return [null, Object.keys(have).map((k) => `${k} ${have[k] ? "yes" : "no"}`).join(", ")];
    });
  }

  // ---- storage ----------------------------------------------------------------------------------------------------
  async function storage() {
    await test("Storage", "localStorage", () => {
      const k = "probe.test";
      localStorage.setItem(k, "1");
      const got = localStorage.getItem(k);
      localStorage.removeItem(k);
      if (got !== "1") throw new Error("a value written was not read back");
      return `works; ${localStorage.length} keys stored by the game`;
    });
    await test("Storage", "localStorage room", () => {
      // The saves (100 slots and 39 automatic ones, each with a small picture) all live here. How much fits?
      const block = "x".repeat(256 * 1024);
      let n = 0;
      try { for (; n < 80; n++) localStorage.setItem(`probe.fill.${n}`, block); } catch { /* full */ }
      for (let i = 0; i <= n; i++) localStorage.removeItem(`probe.fill.${i}`);
      const mb = (n * 256) / 1024;
      return [mb >= 4, `${n >= 80 ? "at least " : ""}${mb.toFixed(2)} million characters fit beside what is stored`];
    });
    await test("Storage", "estimate", async () => {
      if (!navigator.storage || !navigator.storage.estimate) return [null, "navigator.storage.estimate is not here"];
      const e = await within(navigator.storage.estimate(), 3000);
      return [null, `usage ${e.usage}, quota ${e.quota}, persisted ${navigator.storage.persisted ? await navigator.storage.persisted() : "?"}`];
    });
  }

  // ---- the app's file serving ---------------------------------------------------------------------------------------
  async function serving() {
    await test("Serving", "whole file", async () => {
      const r = await fetch(MEDIA + "h264.mp4");
      const buf = await r.arrayBuffer();
      const len = Number(r.headers.get("Content-Length"));
      if (r.status !== 200 || buf.byteLength !== len) throw new Error(`status ${r.status}, ${buf.byteLength} bytes, Content-Length ${len}`);
      return `200, ${buf.byteLength} bytes, ${r.headers.get("Content-Type")}`;
    });
    await test("Serving", "byte range", async () => {
      const whole = new Uint8Array(await bytes(MEDIA + "h264.mp4"));
      const r = await fetch(MEDIA + "h264.mp4", { headers: { Range: "bytes=1000-1999" } });
      const part = new Uint8Array(await r.arrayBuffer());
      const same = part.length === 1000 && part.every((b, i) => b === whole[1000 + i]);
      if (r.status !== 206 || !same) throw new Error(`status ${r.status}, ${part.length} bytes, same bytes ${same}, Content-Range ${r.headers.get("Content-Range")}`);
      return `206, ${r.headers.get("Content-Range")}`;
    });
    await test("Serving", "open-ended and suffix ranges", async () => {
      const size = (await bytes(MEDIA + "h264.mp4")).byteLength;
      const a = await fetch(MEDIA + "h264.mp4", { headers: { Range: `bytes=${size - 10}-` } });
      const b = await fetch(MEDIA + "h264.mp4", { headers: { Range: "bytes=-10" } });
      const la = (await a.arrayBuffer()).byteLength, lb = (await b.arrayBuffer()).byteLength;
      if (a.status !== 206 || b.status !== 206 || la !== 10 || lb !== 10) throw new Error(`statuses ${a.status} ${b.status}, lengths ${la} ${lb}`);
      return `206 and 206, 10 bytes each`;
    });
    await test("Serving", "missing file", async () => {
      const r = await fetch(MEDIA + "no-such-file.bin");
      if (r.status !== 404) throw new Error(`status ${r.status}`);
      return "404";
    });
    await test("Serving", "the game's page", async () => {
      const r = await fetch("/index.html");
      const js = await fetch("/js/main.js");
      if (!r.ok || !js.ok) throw new Error(`index.html ${r.status}, js/main.js ${js.status}`);
      return `index.html ${r.headers.get("Content-Type")}, js/main.js ${js.headers.get("Content-Type")}`;
    });
    await test("Serving", "the game's files", async () => {
      const r = await fetch("/assets/system.json");
      return [null, r.ok ? "installed (assets/system.json is there)" : `not installed (assets/system.json: ${r.status})`];
    });
  }

  // ---- WebGL2, as renderer.js opens it ---------------------------------------------------------------------------------
  let gl = null;
  async function webgl() {
    await test("WebGL2", "context", () => {
      const c = document.createElement("canvas");
      c.width = 1920; c.height = 1080;
      gl = c.getContext("webgl2", { alpha: false, antialias: false, preserveDrawingBuffer: true, powerPreference: "high-performance" });
      if (!gl) throw new Error("getContext('webgl2') gave nothing");
      const info = gl.getExtension("WEBGL_debug_renderer_info");
      return `${gl.getParameter(info ? info.UNMASKED_RENDERER_WEBGL : gl.RENDERER)}; ${gl.getParameter(gl.VERSION)}; largest texture ${gl.getParameter(gl.MAX_TEXTURE_SIZE)}; ` +
        `drawing buffer ${gl.drawingBufferWidth}x${gl.drawingBufferHeight}`;
    });
    await test("WebGL2", "draws", () => {
      if (!gl) throw new Error("no context");
      const sh = (type, src) => { const s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s); if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s)); return s; };
      const p = gl.createProgram();
      gl.attachShader(p, sh(gl.VERTEX_SHADER, "#version 300 es\nin vec2 a;void main(){gl_Position=vec4(a,0.,1.);}"));
      gl.attachShader(p, sh(gl.FRAGMENT_SHADER, "#version 300 es\nprecision highp float;out vec4 o;void main(){o=vec4(1.,.5,.25,1.);}"));
      gl.linkProgram(p);
      if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(p));
      gl.useProgram(p);
      gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
      gl.enableVertexAttribArray(0);
      gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
      gl.viewport(0, 0, 1920, 1080);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
      const px = new Uint8Array(4);
      gl.readPixels(960, 540, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, px);
      const err = gl.getError();
      if (err || px[0] !== 255 || Math.abs(px[1] - 128) > 1 || Math.abs(px[2] - 64) > 1) throw new Error(`pixel ${[...px]}, error ${err}`);
      return `a shader's colour reads back as drawn (${[...px]})`;
    });
  }

  // ---- pictures, as renderer.js reads them -----------------------------------------------------------------------------
  async function pictures() {
    for (const [name, file, needed] of [["AVIF (made by CI)", "image.avif", true], ["AVIF (a standing picture of the game)", "game-picture.avif", true],
      ["WebP (made by CI)", "image.webp", true], ["WebP (interface art of the game)", "game-ui.webp", true]]) {
      await test("Pictures", name, async () => {
        const r = await fetch(MEDIA + file);
        if (!r.ok) return [null, `${file} is not in this build`];
        const blob = await r.blob();
        const t0 = performance.now();
        const bmp = await within(createImageBitmap(blob, { premultiplyAlpha: "premultiply", colorSpaceConversion: "none" }), 8000, "createImageBitmap");
        const ms = performance.now() - t0;
        let tex = "no WebGL to try";
        if (gl) {
          const t = gl.createTexture();
          gl.bindTexture(gl.TEXTURE_2D, t);
          gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
          gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE, bmp);
          const err = gl.getError();
          gl.deleteTexture(t);
          if (err) throw new Error(`texImage2D gave error ${err} for ${bmp.width}x${bmp.height}`);
          tex = "uploads as a texture";
        }
        const img = new Image();
        img.src = MEDIA + file;
        await within(img.decode(), 8000, "<img> decode");
        return [needed ? true : null, `${bmp.width}x${bmp.height}, createImageBitmap ${ms.toFixed(0)} ms, ${tex}, <img> ${img.naturalWidth}x${img.naturalHeight}`];
      });
    }
  }

  // ---- sound, as audio.js makes it ---------------------------------------------------------------------------------------
  let ctx = null, toneBuffer = null;
  const decoder = () => new (window.OfflineAudioContext || window.webkitOfflineAudioContext)(2, 1, 48000);
  async function sound() {
    await test("Sound", "canPlayType", () => {
      const a = document.createElement("audio");
      const types = ['audio/ogg; codecs="opus"', 'audio/mp4; codecs="opus"', 'audio/webm; codecs="opus"', 'audio/x-caf; codecs="opus"', 'audio/mp4; codecs="mp4a.40.2"', "audio/mpeg"];
      return [null, types.map((t) => `${t} -> "${a.canPlayType(t)}"`).join(", ")];
    });
    for (const [name, file, needed] of [["Ogg Opus (made by CI)", "opus.ogg", true], ["Ogg Opus (an interface sound of the game)", "game-opus.ogg", true],
      ["fallback: Opus in MP4", "opus.mp4", false], ["fallback: Opus in WebM", "opus.webm", false], ["fallback: Opus in CAF", "opus.caf", false],
      ["fallback: AAC in M4A", "aac.m4a", false], ["fallback: MP3", "mp3.mp3", false]]) {
      await test("Sound", `decodeAudioData, ${name}`, async () => {
        const r = await fetch(MEDIA + file);
        if (!r.ok) return [null, `${file} is not in this build`];
        const data = await r.arrayBuffer();
        const t0 = performance.now();
        try {
          const buf = await within(decoder().decodeAudioData(data), 8000, "decodeAudioData");
          if (file === "opus.ogg") toneBuffer = buf;
          return [true, `${buf.duration.toFixed(3)} s, ${buf.numberOfChannels} channels, ${buf.sampleRate} Hz, ${(performance.now() - t0).toFixed(0)} ms`];
        } catch (e) {
          return [needed ? false : null, `does not decode: ${says(e)}`];
        }
      });
    }
    await test("Sound", "audio context without a tap", async () => {
      ctx = new (window.AudioContext || window.webkitAudioContext)({ sampleRate: 48000, latencyHint: "interactive" });
      const first = ctx.state;
      if (ctx.state !== "running") { try { await within(ctx.resume(), 1500, "resume"); } catch { /* still suspended */ } }
      const t0 = ctx.currentTime;
      await sleep(400);
      const moved = ctx.currentTime - t0;
      return [ctx.state === "running" && moved > 0.1, `state ${first} at first, then ${ctx.state}; clock moved ${moved.toFixed(3)} s in 0.4 s; ${ctx.sampleRate} Hz, base latency ${ctx.baseLatency}, ` +
        `audioSession ${navigator.audioSession ? navigator.audioSession.type : "none"}`];
    });
    await test("Sound", "plays a decoded sound", async () => {
      if (!ctx || !toneBuffer) throw new Error("no context or nothing decoded");
      const src = ctx.createBufferSource(), gain = ctx.createGain();
      gain.gain.value = 0.05;
      src.buffer = toneBuffer;
      src.connect(gain).connect(ctx.destination);
      const ended = new Promise((r) => { src.onended = r; });
      src.start();
      await within(ended, 4000, "the sound's end");
      return `a ${toneBuffer.duration.toFixed(2)} s sound played to its end`;
    });
  }
  // By ear: with the ring/silent switch on silent, is this heard? (Only a person can tell.)
  function tone() {
    try {
      if (!ctx) ctx = new (window.AudioContext || window.webkitAudioContext)({ sampleRate: 48000 });
      ctx.resume();
      const osc = ctx.createOscillator(), gain = ctx.createGain();
      osc.frequency.value = 440;
      gain.gain.setValueAtTime(0.0001, ctx.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.3, ctx.currentTime + 0.05);
      gain.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + 1.0);
      osc.connect(gain).connect(ctx.destination);
      osc.start();
      osc.stop(ctx.currentTime + 1.05);
      console.info(`probe: test tone asked for by a tap; context ${ctx.state}, audioSession ${navigator.audioSession ? navigator.audioSession.type : "none"}`);
    } catch (e) { console.error(`probe: test tone failed: ${says(e)}`); }
  }

  // ---- movies, as main.js plays them: a <video playsinline> fed by the app's file serving ------------------------------
  const CLIPS = [
    ["AV1 (made by CI, 1080p)", "av1.mp4", 'video/mp4; codecs="av01.0.08M.08"', 30],
    ["AV1 (the game's logo movie)", "game-av1.mp4", 'video/mp4; codecs="av01.0.08M.08"', 30],
    ["fallback: H.264 (made by CI, 1080p)", "h264.mp4", 'video/mp4; codecs="avc1.640028"', 30],
    ["fallback: HEVC (made by CI, 1080p)", "hevc.mp4", 'video/mp4; codecs="hvc1.1.6.L120.90"', 30],
  ];
  function play(url, { seconds = 10, seek = true } = {}) {
    return new Promise((resolve) => {
      const v = document.createElement("video");
      v.setAttribute("playsinline", "");
      v.playsInline = true;
      v.preload = "auto";
      v.volume = 0.05;
      const volume = v.volume;   // (iOS does not let a page set a movie's volume: it reads back 1)
      $("clips").append(v);
      const t0 = performance.now();
      let first = null, sought = null, mutedToStart = false, done = false, seeking = false;
      const finish = (ok, why) => {
        if (done) return;
        done = true;
        clearTimeout(timer);
        const q = v.getVideoPlaybackQuality ? v.getVideoPlaybackQuality() : null;
        const detail = `${why}; ${v.videoWidth}x${v.videoHeight}, ${isFinite(v.duration) ? v.duration.toFixed(2) : "?"} s long, reached ${v.currentTime.toFixed(2)} s, ` +
          `first frame after ${first === null ? "-" : first.toFixed(0)} ms, seek ${sought === null ? "not tried" : sought}, ` +
          `frames ${q ? q.totalVideoFrames : "?"} (dropped ${q ? q.droppedVideoFrames : "?"}), started ${mutedToStart ? "muted (sound refused without a tap)" : "with sound"}, volume reads ${volume}`;
        try { v.pause(); v.removeAttribute("src"); v.load(); } catch { /* gone */ }
        resolve([ok, detail]);
      };
      const timer = setTimeout(() => finish(v.currentTime > 0.5, v.currentTime > 0.5 ? "played (stopped by the probe)" : `no playback within ${seconds} s (readyState ${v.readyState}, networkState ${v.networkState})`), seconds * 1000);
      v.onerror = () => finish(false, `error ${v.error ? `${v.error.code}${v.error.message ? " " + v.error.message : ""}` : "?"}`);
      v.onplaying = () => { if (first === null) first = performance.now() - t0; };
      v.ontimeupdate = () => {
        if (seek && sought === null && !seeking && v.currentTime >= 1.2) {
          seeking = true;
          const at = performance.now();
          v.onseeked = () => { sought = `to 0.30 s in ${(performance.now() - at).toFixed(0)} ms`; };
          v.currentTime = 0.3;
        }
      };
      v.onended = () => finish(true, "played to its end");
      v.src = url;
      v.play().catch((e) => {
        if (e && e.name === "NotAllowedError" && !v.muted) {
          mutedToStart = true;
          v.muted = true;
          v.play().catch((e2) => finish(false, `play() refused: ${says(e2)}`));
        } else finish(false, `play() refused: ${says(e)}`);
      });
    });
  }
  async function movies() {
    const v = document.createElement("video");
    for (const [name, file, type, fps] of CLIPS) {
      const fallback = name.startsWith("fallback");
      await test("Movies", `${name}: what WebKit says`, async () => {
        let caps = "mediaCapabilities not here";
        if (navigator.mediaCapabilities) {
          try {
            const c = await within(navigator.mediaCapabilities.decodingInfo({ type: "file", video: { contentType: type, width: 1920, height: 1080, bitrate: 5000000, framerate: fps } }), 3000);
            caps = `supported ${c.supported}, smooth ${c.smooth}, power efficient ${c.powerEfficient}`;
          } catch (e) { caps = `decodingInfo failed: ${says(e)}`; }
        }
        return [null, `canPlayType "${v.canPlayType(type)}"; ${caps}`];
      });
      await test("Movies", `${name}: plays`, async () => {
        const head = await fetch(MEDIA + file, { method: "HEAD" });
        if (!head.ok) return [null, `${file} is not in this build`];
        const [ok, detail] = await play(MEDIA + file);
        return [ok ? true : fallback ? null : false, detail];
      });
    }
  }

  // ---- fonts --------------------------------------------------------------------------------------------------------------
  async function fonts() {
    await test("Fonts", "a bundled web font", async () => {
      const f = new FontFace("ProbeInter", "url(/fonts/Inter-Latin-Variable.woff2)");
      await within(f.load(), 5000);
      document.fonts.add(f);
      return `Inter-Latin-Variable.woff2 loads (${f.status})`;
    });
    await test("Fonts", "the game's font", async () => {
      const head = await fetch("/assets/fonts/SeuratPro-M.otf", { method: "HEAD" });
      if (!head.ok) return [null, "the game's files are not installed"];
      const f = new FontFace("ProbeSeurat", "url(/assets/fonts/SeuratPro-M.otf)");
      await within(f.load(), 8000);
      return `SeuratPro-M.otf loads (${f.status})`;
    });
  }

  // ---- the game's own files, once they are installed: the heavy cases ---------------------------------------------------------
  async function gameFiles() {
    const there = await fetch("/assets/system.json", { method: "HEAD" }).then((r) => r.ok, () => false);
    if (!there) { add("Game files", "heavy cases", null, "skipped: the game's files are not installed"); return; }
    await test("Game files", "opening movie (op1_arc.mp4, 1080p AV1, 6 s of it)", async () => {
      const [ok, detail] = await play("/assets/movie/op1_arc.mp4", { seconds: 6, seek: false });
      return [ok, detail];
    });
    await test("Game files", "a music track decoded whole", async () => {
      const tables = await (await fetch("/assets/audio_tables.json")).json();
      const name = String(Object.values(tables.bgm)[0]);
      const data = await bytes(`/assets/bgm/${name}.ogg`);
      const t0 = performance.now();
      const buf = await within(decoder().decodeAudioData(data), 30000, "decodeAudioData");
      const mb = (buf.length * buf.numberOfChannels * 4) / 1048576;
      return `${name}.ogg: ${buf.duration.toFixed(1)} s decoded in ${(performance.now() - t0).toFixed(0)} ms, ${mb.toFixed(0)} MB in memory`;
    });
    await test("Game files", "a sound pack", async () => {
      const first = await (await fetch("/assets/pack/index.json")).json();
      const index = await (await fetch(`/assets/pack/${first.index}`)).json();
      const [packName, listing] = index.packs[0];
      const data = await bytes(`/assets/pack/${packName}`);
      return `${first.index} lists ${index.packs.length} packs; ${packName} is ${data.byteLength} bytes with ${listing.length / 2 | 0} sounds`;
    });
  }

  // ---- all of it -----------------------------------------------------------------------------------------------------------------
  let running = false;
  async function run() {
    if (running) return;
    running = true;
    results = [];
    $("rows").textContent = "";
    $("clips").textContent = "";
    $("summary").textContent = "Running...";
    const t0 = performance.now();
    for (const part of [environment, storage, serving, webgl, pictures, sound, movies, fonts, gameFiles]) {
      try { await part(); } catch (e) { add("Probe", part.name, false, `the probe itself failed here: ${says(e)}`); }
    }
    const failed = results.filter((r) => r.state === "fail"), passed = results.filter((r) => r.state === "ok");
    const av1 = state("Movies", "AV1 (the game's logo movie): plays") === "ok" && state("Movies", "AV1 (made by CI, 1080p): plays") === "ok";
    const fallbacks = ["H.264", "HEVC"].filter((c) => results.some((r) => r.group === "Movies" && r.name.startsWith(`fallback: ${c}`) && r.name.endsWith("plays") && r.state !== "fail" && /played/.test(r.detail)));
    const opus = state("Sound", "decodeAudioData, Ogg Opus (made by CI)") === "ok" && state("Sound", "decodeAudioData, Ogg Opus (an interface sound of the game)") === "ok";
    const verdicts = {
      movies: av1 ? "AV1 plays: the game's movies need no fallback here" : `AV1 does NOT play here: the movies will be passed over${fallbacks.length ? `; ${fallbacks.join(" and ")} would play` : ""}`,
      sound: opus ? "Ogg Opus decodes: voices, music and sounds need no fallback here" : "Ogg Opus does NOT decode here: the game would be silent",
    };
    const d = N.device || {};
    const summary = `${d.modelName || "?"}, ${d.system || "?"}${d.simulator ? " (simulator)" : ""}: ${passed.length} passed, ${failed.length} failed, in ${((performance.now() - t0) / 1000).toFixed(1)} s\n` +
      `Movies: ${verdicts.movies}\nSound: ${verdicts.sound}` + (failed.length ? `\nFailed: ${failed.map((r) => `${r.group} / ${r.name}`).join("; ")}` : "");
    $("summary").textContent = summary;
    post({ t: "probe", result: { when: new Date().toISOString(), userAgent: navigator.userAgent, summary, verdicts, av1Plays: av1, oggOpusDecodes: opus, passed: passed.length, failed: failed.length, results } });
    console.info(`probe: done. ${summary.replace(/\n/g, " | ")}`);
    running = false;
  }

  $("again").onclick = run;
  $("tone").onclick = tone;
  $("share").onclick = () => post({ t: "action", name: "share" });
  $("close").onclick = () => post({ t: "action", name: "close-probe" });
  run();
})();
