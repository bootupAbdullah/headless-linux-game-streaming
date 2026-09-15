# The Wayland Pivot, and the Full Stack That Worked

## Why Wayland instead of Xorg

Wayland is the modern replacement protocol for X11 — a rulebook for how a screen gets drawn. Unlike Xorg's forced-fake-monitor hack (`ConnectedMonitor` + synthetic EDID — see [`02-xorg-dead-end.md`](02-xorg-dead-end.md)), Wayland compositors have **real, officially supported** headless virtual-display capability (confirmed in GNOME's Mutter since 2021, and available in KDE's KWin). Same end goal — a display something can draw into with nothing physically attached — but a fundamentally different, actually-supported mechanism instead of tricking a driver into a state it was never designed to cleanly leave.

This is the layer that replaces the entire broken Xorg approach, and it's the reason the project survived that dead end instead of stalling on it.

## Reference project: Sunveil

Rather than building this blind, an existing public project called [**Sunveil**](https://github.com/ImStillBlue/sunshine-virtual-display) (repo: `sunshine-virtual-display`, by `ImStillBlue`) was found right after the Xorg approach failed. It solves the same problem — an on-demand, headless virtual display for Sunshine streaming — on closely matching hardware and software: KDE Plasma 6, Wayland, NVIDIA proprietary drivers.

The actual mechanism copied from it was `krfb-virtualmonitor` + `kscreen-doctor` (rather than a raw KWin-only headless approach originally assumed). Sunveil's `stream-start.sh`/`stream-end.sh` hook scripts were read in full and adapted into this project's own `start-display.sh`/`stop-display.sh` (see [`05-scripts-and-orchestration.md`](05-scripts-and-orchestration.md)) — originally built for Sunshine's automatic per-connection triggering, deliberately changed here to manual/on-demand triggering instead.

## The stack, in order

```
 1. Hardware
 2. Operating system (Ubuntu)
 3. GPU driver (NVIDIA)
 4. Desktop / compositor session (Plasma + KWin)
 5. Output (screen — physical or virtual)
 6. PipeWire (screen-capture plumbing)
 7. Sunshine (capture, encode, stream, input)
 8. RetroArch (the emulator)
 9. Network path (firewall, discovery)
10. Moonlight (client)
```

Each layer talks only to the one directly above and below it — which matters when troubleshooting: a problem at layer 7 is very unlikely to be caused by layer 2.

### 1. Hardware

The physical machine. GPU role: none yet — this is just the silicon existing, the resource every layer above eventually draws on. See [`01-hardware-and-driver.md`](01-hardware-and-driver.md) for specs.

### 2. Operating system (Ubuntu 26.04)

The base OS and kernel. GPU role: the kernel loads generic hardware detection for the GPU (recognizes a PCI device is present) but doesn't know how to actually use it — that comes from the driver, one layer up.

### 3. GPU driver (NVIDIA proprietary, 580.173.02)

The software translation layer that lets everything above it talk to the GPU. Two separate capabilities live here:

- **Rendering** (drawing pixels) — fully supported, used by KWin (layer 4) and RetroArch (layer 8).
- **NVENC** (hardware video encoding) — capped at API 13.0, a permanent ceiling for this GPU generation. Full detail in [`01-hardware-and-driver.md`](01-hardware-and-driver.md).

### 4. Desktop / compositor session (Plasma + KWin)

An invisible, headless desktop session — no taskbar, no visible UI, started manually via a `systemd-run` command (not automatic login/SDDM — see [`04-session-startup-systemd-run.md`](04-session-startup-systemd-run.md) for why that's necessary). Runs continuously once started; survives idle time and multi-day gaps, but does **not** survive a reboot automatically.

Key packages: `plasma-workspace`, `kwin-wayland`, `kscreen`, `krfb`.

**GPU role — this is the first layer that actively uses the GPU for real work.** KWin (the compositor) uses the GPU to render/composite whatever's on screen, even an empty virtual screen — the same fundamental job a desktop GPU always does, just with nothing visually interesting happening. This is rendering, not encoding.

**Resource footprint (measured):** ~300MB RAM combined across the three core processes (`startplasma-wayland`, `kwin_wayland_wrapper`, `kwin_wayland`), 0% CPU at idle.

**Known, accepted quirks:** the visible desktop shell (`plasmashell` — taskbar, wallpaper, launcher) fails to start every time — expected and harmless, since this headless setup never needs a visible shell, only the compositor itself. A screen-lock crash on the very first session (missing Wayland `layer-shell` support) was root-caused and fixed by disabling autolock.

### 5. Output (screen — physical or virtual)

A "screen" KWin can draw into. Two kinds exist on this kind of hardware: the real, physical panel (never has a monitor attached, but exists as hardware regardless) and a virtual output created on demand by `krfb-virtualmonitor`, existing only in system/GPU memory.

Controlled by `start-display.sh` / `stop-display.sh` (adapted from Sunveil) — create the virtual output, set it primary, disable the physical one; and reverse all of that on teardown. Tested repeatedly, including surviving a full reboot.

**GPU role:** the output *is* a block of GPU memory (a framebuffer) that KWin writes pixel data into. Creating a virtual output doesn't add new GPU capability — it's KWin using the same rendering capability from layer 4, targeting a different, invisible destination instead of a real monitor.

### 6. PipeWire (screen-capture plumbing)

A system service that passes audio/video data streams between programs — specifically, the mechanism KWin uses to let an external program (Sunshine) grab a copy of what's rendered in layer 5's output.

Key packages: `pipewire`, `pipewire-bin`, `pipewire-pulse`, `wireplumber`.

**A real gap found and fixed:** only KDE's PipeWire-*aware libraries* were installed initially (pulled in automatically as a side effect of installing Plasma) — the actual PipeWire *service* was completely absent. This wasn't discovered until Sunshine tried to use it and silently failed with no obvious symptom; installing the full stack fixed it completely.

**GPU role:** none directly — pure data plumbing between KWin (which has GPU-rendered pixel data) and Sunshine (which wants to read it).

### 7. Sunshine (capture, encode, stream, input)

The streaming host software: captures frames via PipeWire, compresses them into a video stream, sends that stream to the client, and receives input back.

**Config:** `capture = kwin`, pointed at the virtual output name — tells Sunshine explicitly to use the KWin/PipeWire capture path rather than its default `kmsgrab` method, which only works on physical monitors and would not see a virtual output at all.

**GPU role — the most GPU-relevant layer, in two separate ways:**
- **Capture:** happens via PipeWire, pulling already-rendered GPU frame data — no additional GPU work here.
- **Encoding:** this is where the NVENC ceiling (layer 3) becomes visible. Sunshine tries hardware encoders in order — `nvenc` (fails, driver/API mismatch, confirmed permanent), `vulkan` (fails, missing video-encoding extension for this GPU), `vaapi` (fails, required driver files not installed) — and falls back to **`libx264`**, a software (CPU-based) encoder. Confirmed working, and the permanent, correct configuration for this hardware, not a temporary gap.

**Other real issues fixed here:** a CSRF error blocking the web dashboard login (fixed via `csrf_allowed_origins` in `sunshine.conf`); a `Failed to create client: Daemon not running` error traced (after an initial wrong guess involving the system tray) to `avahi-daemon` being completely absent.

### 8. RetroArch (SNES emulator, Snes9x core)

Runs the actual game logic and renders each frame into the output layer 5 provides.

**A packaging gotcha:** Ubuntu's RetroArch package deliberately omits the in-app "Core Downloader" — the SNES core had to be installed directly as its own package (`libretro-snes9x`).

**Getting it to draw somewhere:** an earlier plan to route RetroArch through an X11-compatibility shim was abandoned in favor of pointing it directly at the Wayland session (`WAYLAND_DISPLAY`) — simpler, and avoids reintroducing any of the old X11-layer problems.

**On legality, handled deliberately:** homebrew/fan-made SNES games (freely available, made specifically for public use) were used for testing, not commercial ROMs. A personally-owned cartridge can legally be dumped for private backup/personal use; distributing or publicly streaming a copyrighted commercial ROM is a separate, unresolved legal line, and not one this project crosses.

**First test, a red herring:** the first ROM tried loaded to a black screen — correctly isolated as a quirk specific to that ROM's internal memory-mapping header, not a pipeline failure. A second ROM loaded and ran perfectly: video, audio, and keyboard input all working live.

**GPU role:** RetroArch renders via OpenGL or Vulkan — the second real GPU-rendering consumer in this chain, alongside KWin's own compositing.

### 9. Network path (firewall, discovery)

Everything that gets the video stream and input data to the client and back, restricted to trusted devices only:

- A firewall with default-deny on incoming traffic — every port used (the display tool's VNC-style port, and Sunshine's ports) individually scoped, never one blanket "allow everything" rule, never exposed to the public internet.
- A private mesh VPN, so the server is reachable from anywhere without ever being exposed publicly.
- mDNS/local-network auto-discovery (Avahi) — works on the same physical network; correctly, expectedly does *not* work across a VPN tunnel, since that's a known limitation of the discovery protocol, not a bug. Across the VPN, the server is reached by its VPN address directly.

**GPU role:** none. Pure networking.

### 10. Moonlight (client)

The receiving app on the client machine. Connects to Sunshine, decodes the incoming video/audio, displays it, and captures local keyboard/mouse/controller input to send back.

**Pairing:** completed after clearing one stale, half-finished pairing attempt — a normal one-time hiccup.

**A UX wrinkle, diagnosed and fixed:** by default, the client captures the mouse the way a game would (locked to the window) — disorienting for anything else, only escapable via a system-level window-switch shortcut. A client-side setting ("optimize mouse for remote desktop instead of games") fixed this cleanly once found.

**GPU role:** happens on the **client's** GPU, not the server's — decoding a compressed video stream back into a displayable picture is itself GPU-accelerated work, on entirely separate hardware from the server's GPU.

## The full chain, end to end

```
RetroArch (SNES emulator, Snes9x core)
   ↓ renders game frames into
KWin (Wayland compositor) — drawing onto a virtual display
   ↓ virtual display created/destroyed by
krfb-virtualmonitor + kscreen-doctor  (start-display.sh / stop-display.sh)
   ↓ frames captured by
PipeWire (screen capture)
   ↓ handed to
Sunshine (capture = kwin → libx264 software video encoding, Opus audio)
   ↓ discovered via local-network mDNS, or a direct VPN address remotely
   ↓ streamed over the network, through per-port firewall rules,
   ↓ across a private mesh VPN (no public internet exposure)
Moonlight (client)
   ↓ decodes video + audio, displays them
   ↓ captures local keyboard/mouse/controller input
   ↑ sends input back the same path, in reverse, to RetroArch
```

**Milestone confirmed:** a real, homebrew SNES game, running on a self-hosted headless Linux server, streamed live with working video, audio, and input to a client machine — over a private network, with no part of the chain exposed to the public internet.

## Summary — where the GPU is actually involved

| Layer | GPU involvement |
|---|---|
| 1. Hardware | GPU physically exists, not yet in use |
| 2. OS | Detects GPU exists, no driver-level use |
| 3. GPU driver | **Enables all GPU use** — rendering (full support) and NVENC (capped, permanent ceiling) |
| 4. Compositor (KWin) | **Uses GPU for rendering/compositing** |
| 5. Output | Is GPU memory (framebuffer), no separate GPU work |
| 6. PipeWire | No GPU involvement — data plumbing only |
| 7. Sunshine | **Attempts GPU encoding (fails, permanently), falls back to CPU encoding (works)** |
| 8. RetroArch | **Uses GPU for rendering the emulated game** |
| 9. Network | No GPU involvement |
| 10. Moonlight (client) | Uses the **client's** GPU for video decode — different hardware entirely |

**Net picture:** the GPU does real, necessary work rendering (layers 4 and 8). It was *supposed* to also help at layer 7 (encoding) but can't, permanently, due to a driver/hardware generation mismatch — that job falls to the CPU instead, which handles it comfortably given this machine's proven headroom.

## Known, accepted, low-priority loose ends

- One specific ROM doesn't run correctly due to its own internal header quirk — not worth chasing, other ROMs work fine.
- A cosmetic bug in Sunshine's web dashboard (a tray-icon checkbox that doesn't visually persist, though the underlying setting is correctly applied).
- Two harmless permission warnings in Sunshine's logs (`setpriority`) with no observed effect on stream quality.
