# Roadmap

## Done — Foundation

- Server hardware validated, healthy, reboot-proof
- Plasma Wayland session — reliably reproducible from cold boot
- Virtual display create/destroy — tested repeatedly, reboot-proof
- Firewall properly scoped throughout

## Done — Sunshine

- Installed, `capture = kwin` working, PipeWire fixed, NVENC confirmed permanently unavailable (software encoding accepted, confirmed low CPU impact — ~1 of 6 cores during real gameplay)
- Web UI, CSRF, avahi-daemon all fixed — zero startup errors

## Done — Moonlight & pairing

- Installed, paired, first successful stream (video + audio)
- Mouse capture issue fixed

## Done — RetroArch

- Installed, Snes9x core installed, confirmed working end-to-end with real gameplay + audio
- Set up as its own Sunshine Application — launches directly from Moonlight, no terminal required
- Clean shutdown confirmed — quitting RetroArch ends the stream cleanly
- Fullscreen fixed, menu navigation clarified

## Done — System integration

- Full system map written — documents exactly what runs where, and how each layer starts
- `rungames.sh` / `stopgames.sh` built — chains Plasma session → virtual display → Sunshine, checking each layer and skipping what's already running; fully idempotent
- Client-side `rungames` / `stopgames` wrapper functions, version-controlled in a private dotfiles repo
- **End-to-end one-command flow achieved:** one command on the client → wakes the server (harmless if already on) → brings up the full stack remotely → opens the streaming client → click the emulator → playing.

## Known, accepted, low-priority

- Starting the Plasma session requires an interactive password prompt — genuine remaining limitation, not yet solved
- One specific ROM has a header quirk unrelated to the pipeline
- A cosmetic checkbox bug in Sunshine's web UI
- Two harmless `setpriority` permission warnings, no observed impact

## Next up

- **Convert `rungames.sh`/`stopgames.sh` into `systemd --user` services** — the honest, achievable version of "isolated and cleanly managed." Real containerization was assessed and set aside: KWin needs real access to the GPU (`/dev/dri/*`) to composite anything at all; the streaming host's input system needs direct access to `/dev/uinput`/`/dev/uhid` to create virtual input devices — exactly the kind of low-level hardware access containers are designed to restrict; and the screen-capture path needs the Wayland socket and D-Bus session, tightly coupled to the specific logged-in session rather than something that isolates cleanly. Making this work in a container would mean passing through nearly all of that access anyway (privileged mode, device mounts, shared sockets) — the packaging convenience of a container, with most of the actual isolation benefit lost. `systemd --user` services get defined start/stop/restart behavior, logging, and dependency ordering (essentially what `rungames.sh` does manually right now) without fighting that GPU/input access problem.
- As part of that: revisit whether stopping should also tear down the Plasma session itself, trading the password-prompt-on-restart cost for a fully clean idle state.
- **Autologin at boot** — the one remaining piece that would eliminate the password-prompt step entirely, making the Plasma session already-running after every reboot.
- Acquire a real controller, test gamepad input through the streaming host's virtual-input path.
- Consider a cartridge-dumping device for a personal, legally-owned game library.
- Test a full reboot cycle with `rungames.sh`/`stopgames.sh` in the loop.
