# YouTube 3D Vision

A Chrome extension (Manifest V3) that turns regular YouTube videos into stereoscopic 3D in real time — directly on the YouTube watch page. It runs a real AI depth-estimation model (MiDaS v2.1 small, ONNX) fully locally in your browser and renders depth-based left/right views with WebGL2.

**This is a working prototype.** It is not affiliated with YouTube/Google.

## What it does

- Adds a **3D Vision button** to the real YouTube player controls (`ytp-right-controls`).
- Reads frames from the playing video (no download, no re-hosting) and estimates a **per-pixel depth map with a real neural network** — no fake/hardcoded gradients.
- Renders two views with depth-driven horizontal disparity using a modern renderer stack — **WebGPU (WGSL) preferred, WebGL2 (GLSL ES 3.00) as automatic fallback**. (Note: there is no "WebGL3" — the API that follows WebGL2 is WebGPU):
  - **Anaglyph** (red-cyan glasses)
  - **Side-by-side** (3D TVs / VR viewers)
  - **2D** passthrough
  - **360° mode**: drag- or head-tracked equirectangular viewing (DeviceOrientation on devices with a sensor) *for genuine 360 uploads only* — it does not invent unseen surroundings for flat videos
- Live panel controls: on/off, mode, depth strength, eye separation, convergence, Align X / Y screen alignment, quality, backend, FPS / inference latency / reuse / JS-heap memory readouts, GPU-vs-CPU + renderer status, reset.
- Handles YouTube SPA navigation (`yt-navigate-finish`), fullscreen, seeking, pause, and video changes; leaves normal playback and controls untouched.
- Fails gracefully on protected content: a frame-readability probe detects DRM-blocked/cross-origin frames, shows a notice, and changes nothing about playback. No DRM, paywall or access control is bypassed.
- **Privacy:** all processing is local. No frames, history or telemetry ever leave the machine.

## Verified vs. untested — honest status

Verified in this build (Chrome for Testing 153, headless, Linux; see `tests/results/browser-test.md`):

| Feature | Status |
| --- | --- |
| Extension loads; 3D button + panel + overlay canvas injected into real `youtube.com` player | Verified on a real watch page earlier in the test session (the datacenter IP later got a YouTube CAPTCHA wall, so re-runs were recorded as skipped) |
| Full pipeline on real video playback (script injection → player button → model load → real inference → WebGL2 stereo output) | **14/14 automated browser checks passed** on a local stand-in page replicating the YouTube player DOM (`#movie_player`, `.html5-video-container`, `.ytp-right-controls`) with a real VP9 video |
| AI inference produces a valid depth map | Verified with the actual ONNX model in Python (onnxruntime) and in-browser (ONNX Runtime Web, wasm) |
| Fullscreen, video change (SPA) and screen alignment | A17/A18/A20: overlay stays fitted + active in fullscreen; pipeline re-attaches to a replaced video element; alignment sliders shift the frame (pixel-measured) |
| Protected (unreadable) videos fail gracefully | A2/P1-P4: cross-origin fixture verified unreadable; enabling shows a clear error, no overlay, playback untouched, no page errors |
| 360 head-tracked viewing | A19: synthetic DeviceOrientation events rotate the rendered view (pixel-measured) |
| Memory monitoring | A16: live JS-heap readout in the panel |
| Left/right views have measurable disparity | Measured: anaglyph R-G split 0 gray levels at zero separation vs mean 21 / p95 77 at full separation, on the same paused frame |
| MiDaS I/O contract | Empirically confirmed: input `[1,3,256,256]` float32 (ImageNet-normalized), output `[1,256,256]`, higher = nearer |
| Measured performance on the test VM | 5–7 rendered fps, ~3–6 s per inference, CPU (wasm). This is a weak shared VM with software WebGL (SwiftShader) — real hardware will be substantially faster, but no specific number is claimed for hardware we did not test. |
| Actual YouTube video playback with 3D active | **Not verifiable from this test environment** (media CDN blocked + bot-check wall). Same code path as the local stand-in test, but treat as untested until you try it on your machine. |
| Renderer stack | WebGPU renderer auto-selected and initialized (WGSL compiled, pipelines created, submits error-free); in the test VM's software-GPU headless environment WebGPU *canvas presentation* is broken (an isolated red-clear WebGPU canvas also stays blank), so pixel accuracy was verified on the WebGL2 renderer after switching via the Backend selector — that switch itself is a verified check. On hardware with a working WebGPU compositor the extension stays on WebGPU; the `WASM` backend option forces the WebGL2 path. |
| Mobile browsers | Untested. (MV3 extensions on Android Chrome are limited.) |
| Fullscreen with real GPU + WebGPU backend | Not tested (test environment had no GPU; worker supports WebGPU with automatic wasm fallback and reports which backend is live) |

## Installation

1. Requirements: Chromium-based browser with extension support (Chrome/Edge/Brave desktop).
2. `chrome://extensions` → enable **Developer mode** → **Load unpacked** → select this folder.
3. That's it. **The AI model ships inside the extension** (`models/midas_v21_small_256.onnx`), so 3D works instantly on the very first video — zero downloads, ever, even offline.

   Fallback for builds without the bundled file (e.g. store-size-limited packaging): the inference worker fetches the model itself on first use from a public CDN mirror, stores the **whole model in IndexedDB on the site's origin** (shared by every YouTube tab), and every later video is instant from that cache. The panel shows live progress ("Getting the 3D model — 42% (first time only)") on that one path. `npm run fetch-model` or manually placing the file into `models/` pre-seeds it the same way; a bundled file always wins over the cache.
4. Open any normal (non-DRM) YouTube video, click the **3D Vision** button in the player controls, and switch the panel toggle on. Put on red-cyan glasses for anaglyph mode.

**Model:** MiDaS v2.1 small (Intel ISL), MIT license — https://github.com/isl-org/MiDaS. The model is fetched on first use from a public CDN: the official `isl-org/MiDaS` GitHub release is listed first, but that host does not send CORS headers, so in practice the Hugging Face mirrors serve the file (they echo `Access-Control-Allow-Origin`). The mirror file is the same network with different input/output tensor names (`input_image`/`output_depth` instead of `0`/`797`); the worker reads tensor names dynamically from the session, so both variants run identically (both verified standalone with Python onnxruntime). The fetch is streamed with progress and the whole file is stored once in IndexedDB.

## Architecture

```
manifest.json            MV3 manifest (content script + service worker + popup)
content.js               loader: dynamic-imports src/main.js into the isolated world
src/main.js              orchestrator: lifecycle, enable/disable, wiring
src/video-detector.js    finds <video>/player, SPA nav, fullscreen; DRM/frame probe
src/frame-processor.js   rAF render loop + adaptive async inference cadence
src/depth-engine.js      module Web Worker: ONNX Runtime Web (MiDaS small), temporal reuse
src/stereo-renderer.js   WebGL2 overlay canvas: anaglyph/SBS/2D/360 shaders (GLSL ES 3.00)
src/stereo-renderer-webgpu.js  WebGPU renderer (WGSL): external-texture video
                         import, single-pass side-by-side, presentation watchdog
src/renderer-factory.js  chooses WebGPU when available, WebGL2 otherwise
src/panel.js             player button + floating control panel
src/settings.js          defaults, validation, chrome.storage sync
src/lib/worker-launch.js blob-worker launcher (content scripts cannot spawn
                         cross-origin chrome-extension workers directly)
src/lib/stereo-math.js   pure stereo/disparity math (unit-tested)
src/lib/depth-post.js     pure depth normalization + temporal reuse logic (unit-tested)
src/lib/idb.js           IndexedDB helper (model cache)
src/lib/model-store.js   CDN model sources + streamed download with progress + whole-model IndexedDB cache (used by the inference worker; unit-tested with mocked fetch/IDB)
shaders/*.glsl           GLSL ES 3.00 shader sources
background.js            service worker: relays the model-ready state from YouTube tabs to the popup (status strings only)
popup.html / popup.js    plain-language settings + readiness card (no download button; setup is fully automatic on the watch page)
scripts/fetch-model.mjs  CLI model downloader
tests/                   node unit tests + browser end-to-end test + results
vendor/onnxruntime-web/  ONNX Runtime Web (ESM + wasm), unmodified
models/                  midas_v21_small_256.onnx (bundled: instant first use; CDN+IndexedDB fallback when absent)
```

How the 3D works: the depth model produces a relative nearness map (256×256, 1 = closest). The stereo shader computes a per-pixel horizontal sampling shift `shift = (nearness − convergence) × disparity` and builds the left view by sampling the video shifted by `+shift`, the right view by `−shift`. Disocclusions are handled by edge-clamped sampling (stretch); depth is reused across frames when the scene barely moves (frame-difference check in the worker).

Known MV3 quirk handled by `worker-launch.js`: content scripts cannot construct a `Worker` from a `chrome-extension://` URL (cross-origin restriction), so the worker source is fetched, its imports rewritten to absolute extension URLs, and the worker instantiated from a blob. That is also why the worker receives the model/wasm URLs via its `init` message (blob workers have no `chrome.*` access). The model itself is loaded inside the worker: bundled file (dev path) → the site-origin IndexedDB cache (instant after first use) → a one-time CORS fetch from a CDN mirror, whose bytes are then stored whole into that same IndexedDB. This all happens on the page origin, so no `chrome.runtime` messaging of binary payloads is ever needed (extension messages are JSON-only and cannot carry ArrayBuffers).

## Testing

```bash
npm test                 # 22 unit tests (settings, stereo math, depth post, bundle)
node browser-test.mjs    # end-to-end browser test (requires local chrome + puppeteer-core)
```

The browser test has two phases (details and results in `tests/results/browser-test.md`):

- **Phase D** — bundled-model flow (the shipped configuration): model included in the package, fresh profile, first use must be instant with zero downloads — (D1) model bundled, (D2) "AI depth active" in 20 s with no download status ever shown, (D3) page IndexedDB has no model record (nothing was fetched), (D4) measurable anaglyph disparity from the bundled model, (D5) popup "Everything is ready" via the bundled-model check, (D6) no page errors. 6/6 passed.
- **Phase C** — zero-click model flow (fallback path, exercised with the model removed from the extension): with **no model file bundled anywhere**, enabling 3D on a fresh profile must result in (C1) no bundled model, (C2) "AI depth active" purely from the automatic one-time CDN fetch by the worker, (C4) measurable anaglyph disparity from the CDN-sourced model, (C5) the whole 66.4 MB model stored in the page's IndexedDB and the popup reporting "Everything is ready" via the background status relay, (C6) no page errors. 5/5 passed (Chrome for Testing 153, headless, wasm/WebGL2 after the documented WebGPU-presentation fallback).
- **Phase A** — local YouTube-DOM stand-in served at `http://127.0.0.1:8123` (a test copy of the extension with an extra localhost match pattern), real VP9 playback: checks button injection, playback coexistence, model load, live inference, measurable disparity (sep 0 vs 1 on the same paused frame), SBS, 2D, seeking, pause handling, FPS/latency readouts, honest backend reporting, and absence of page errors. Screenshots in `tests/results/`.
- **Phase B** — the real `youtube.com` watch page: extension load/injection checks.

The model itself was additionally verified standalone with Python `onnxruntime` (I/O shapes, deterministic output, near/far ordering, depth-map visualizations in `tests/fixtures/`).

## Known limitations

- Inference runs single-threaded wasm on most pages (YouTube is not cross-origin-isolated → no `SharedArrayBuffer`). WebGPU is used automatically when available. On modest hardware expect a depth update every few hundred ms; rendering stays smooth because disparity is applied per rendered frame from the latest depth map.
- MiDaS small is a relative-depth model: depth ordering is meaningful, absolute distances are not.
- Stereo re-projection is 2.5D: disocclusions are edge-stretched, so thin foreground structures can show minor smearing. The strength/eye-separation/convergence sliders exist to keep the effect comfortable.
- DRM-protected videos (most premium/studio content) cannot be processed; the extension detects this and stays idle. Free, non-DRM videos are the target.
- 360 mode only re-projects genuine 360 uploads; it cannot reveal off-camera content of flat videos.
- Not tested on real consumer GPUs, VR headsets, or mobile browsers.

## Roadmap

1. Fallback stereo from motion: compute camera parallax from scene motion to complement AI depth.
2. Inpainting pass for disocclusions (horizontal coherence filter in shader).
3. Depth-map temporal smoothing (currently reuse-or-replace).
4. Options page with per-channel presets; per-site enable list.
5. Quantized (int8) MiDaS for faster inference on the WebGPU path.
6. 360 mode with device-orientation head tracking (API already wired for drag).
7. Runtime WebGPU pixel verification on real hardware (blocked in this environment by broken software-WebGPU compositing).
```

## License notes

Extension code: prototype, provided as-is. MiDaS model: MIT (Intel ISL). ONNX Runtime Web: MIT. YouTube is a trademark of Google; this project is not affiliated with or endorsed by Google.
