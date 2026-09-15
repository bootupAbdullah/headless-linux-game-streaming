# Headless Linux Game Streaming: A Fake Monitor, an Unkillable Driver, and the Wayland Fix That Worked

A build log for turning a headless Linux server with no monitor attached into a working game-streaming setup — a real display created entirely in software, a SNES emulator rendering into it, and a streaming host sending that over the network to another machine.

**If you landed here from a Reddit/forum thread about an NVIDIA driver hanging on shutdown after using `ConnectedMonitor` + `CustomEDID`, or `nvidia: [drm] *ERROR* Disabling all crtc's during unload failed with -22`, start with [`docs/02-xorg-dead-end.md`](docs/02-xorg-dead-end.md).** That's the specific dead end this repo exists to document, so nobody else has to rediscover it from scratch.

## What this actually is

Not a polished product, not a generic tutorial. This is one specific build, on one specific piece of hardware, documented in enough detail that someone hitting the same wall can either follow the exact same path or at least skip the parts that don't work.

The end result: a single command run from a Mac wakes the server, brings up every layer of the stack in order, and opens the streaming client — ready to click into a running SNES emulator, streamed live over the network.

## The short version

The first approach (Xorg, tricking the NVIDIA driver into believing a monitor was plugged in via `ConnectedMonitor` + a synthetic EDID) worked perfectly at startup and then hung the entire machine, unrecoverably, on every single shutdown — a genuine driver bug, not a config mistake, confirmed via kernel stack traces and fully documented in `docs/02-xorg-dead-end.md`.

That dead end forced a pivot to a fundamentally different, actually-supported mechanism: a Wayland compositor (KDE Plasma's KWin) with a real, officially-supported headless virtual display (`krfb-virtualmonitor`), adapted from an existing public reference project ([Sunveil](https://github.com/ImStillBlue/sunshine-virtual-display)) that had already solved the same problem on similar hardware. That path worked, was proven reboot-safe, and became the permanent foundation.

## The stack, top to bottom

```
RetroArch (SNES emulator, Snes9x core)
   ↓ renders frames into
KWin (Wayland compositor) — drawing onto a virtual display
   ↓ virtual display created/destroyed by
krfb-virtualmonitor + kscreen-doctor  (scripts/start-display.sh / stop-display.sh)
   ↓ frames captured by
PipeWire (screen capture)
   ↓ handed to
Sunshine (capture = kwin → libx264 software video encoding, Opus audio)
   ↓ streamed over the network
Moonlight (client, on another machine)
   ↓ decodes video + audio, displays them
   ↓ captures local keyboard/mouse/controller input
   ↑ sends input back the same path, in reverse, to RetroArch
```

Full detail on every layer, including exactly where (and where not) the GPU is involved: [`docs/03-wayland-pivot-and-full-stack.md`](docs/03-wayland-pivot-and-full-stack.md).

## Why the "obvious" approach doesn't work on this hardware

An NVIDIA Quadro P600 (Pascal generation) on the Legacy 580.x driver branch — the newest branch this GPU generation will ever receive — cannot cleanly tear down an Xorg session that was faked into existing via `ConnectedMonitor`. Startup is flawless. Shutdown gets the whole machine stuck in an uninterruptible kernel-mode wait, immune to `kill -9`, recoverable only with a hard power-off.

Full diagnosis, evidence, and the (still partially open) forum question this project asked publicly: [`docs/02-xorg-dead-end.md`](docs/02-xorg-dead-end.md).

## Docs index

| Doc | Covers |
|---|---|
| [`docs/01-hardware-and-driver.md`](docs/01-hardware-and-driver.md) | The hardware, the OS, the GPU/driver situation, and the permanent NVENC ceiling |
| [`docs/02-xorg-dead-end.md`](docs/02-xorg-dead-end.md) | The Xorg approach, why it failed, and the full diagnosis (start here if you're here from the shutdown-hang issue) |
| [`docs/03-wayland-pivot-and-full-stack.md`](docs/03-wayland-pivot-and-full-stack.md) | The working architecture, layer by layer, end to end |
| [`docs/04-session-startup-systemd-run.md`](docs/04-session-startup-systemd-run.md) | Getting a headless Plasma session to actually start over SSH |
| [`docs/05-scripts-and-orchestration.md`](docs/05-scripts-and-orchestration.md) | What each script does and how they chain together |
| [`docs/glossary.md`](docs/glossary.md) | Plain-language definitions for every term used above |
| [`ROADMAP.md`](ROADMAP.md) | What's solved, what's deliberately deferred, what's next |

## Scripts

All in [`scripts/`](scripts/), documented in [`docs/05-scripts-and-orchestration.md`](docs/05-scripts-and-orchestration.md). Rename the placeholder identifiers (see the top of each script) before use — these are written to be adapted, not run as-is against someone else's hostname.

- `start-display.sh` / `stop-display.sh` — create/destroy the virtual display
- `rungames.sh` / `stopgames.sh` — bring the whole stack up/down, idempotently
- `diagnose.sh` — read-only, full-state snapshot for "did it actually work" questions

## Credit

The virtual-display mechanism (`krfb-virtualmonitor` + `kscreen-doctor`, and the general shape of the start/stop hook scripts) is adapted from [**Sunveil**](https://github.com/ImStillBlue/sunshine-virtual-display) by [ImStillBlue](https://github.com/ImStillBlue), a public reference project solving the same headless-virtual-display problem for Sunshine on KDE Plasma 6 + Wayland. Sunveil's own scripts trigger automatically per Sunshine connection (`global_prep_cmd`); this project's scripts were deliberately adapted to manual/on-demand triggering instead.

The `systemd-run` fix for starting a Plasma session over a bare SSH connection was found via a KDE Discuss forum thread describing the identical use case, including a follow-up fix (`WAYLAND_DISPLAY=wayland-0`) from a user going by `pixeled` who had hit the same second-order problem. Full detail and reasoning in `docs/04-session-startup-systemd-run.md`.

## License

See [`LICENSE`](LICENSE).
