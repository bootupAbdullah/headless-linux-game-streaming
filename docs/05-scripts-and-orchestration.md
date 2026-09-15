# Scripts and Orchestration

All scripts live in [`../scripts/`](../scripts/). They're written to be adapted, not run unmodified — the placeholder name `myserver` (used as the virtual-display label) should be replaced with something specific to your own machine before use, and the placeholder VNC password in `start-display.sh` must be changed before any real use.

## `start-display.sh` / `stop-display.sh`

Adapted from [Sunveil](https://github.com/ImStillBlue/sunshine-virtual-display), originally a Sunshine `stream-start`/`stream-end` hook triggered automatically on client connect. This version is run manually.

**`start-display.sh`:**
1. Records which physical outputs are currently enabled (so they can be restored later).
2. Launches `krfb-virtualmonitor` to create a virtual display at a fixed resolution/refresh rate.
3. Sets that virtual display as the active/primary output.
4. Disables the real physical output.

Fails safe: if the virtual output never appears, it does **not** touch the physical output, and exits with an error rather than leaving the machine in a half-changed state.

**`stop-display.sh`:** reverses all of it — re-enables whatever was on before, kills the virtual monitor process, restores the original primary display. Safe to run even if `start-display.sh` failed partway; it only acts on state it can actually find, and warns rather than errors if that state is missing.

Both scripts set `WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR`, and `DBUS_SESSION_BUS_ADDRESS` themselves at the top, so they work no matter which SSH session they're run from — the gotcha covered in [`04-session-startup-systemd-run.md`](04-session-startup-systemd-run.md).

## `rungames.sh` / `stopgames.sh`

Chain the full stack together, checking each layer before acting so both scripts are safe to run repeatedly (idempotent).

**`rungames.sh`** brings up, in order:
1. **Plasma Wayland session** — checks if `kwin_wayland` is already running; if not, runs the `systemd-run` command from [`04-session-startup-systemd-run.md`](04-session-startup-systemd-run.md) and waits (up to 20 seconds) for the `wayland-0` socket to appear before continuing.
2. **Virtual display** — checks `kscreen-doctor -o` for the virtual output by name; if not present, runs `start-display.sh`.
3. **Sunshine** — checks if the process is already running; if not, starts it detached (`setsid ... &`, `disown`) so it survives the SSH session ending, and confirms it actually came up before declaring success.

**Known limitation, by design:** starting the Plasma session (step 1) requires an interactive password prompt. If run over SSH, that means using `ssh -t` so the prompt can actually be answered. This goes away once autologin-at-boot is set up (see `ROADMAP.md`) — at that point step 1 will already be satisfied on every run and the script just skips it.

**`stopgames.sh`** does exactly two things, deliberately narrow in scope:
1. Kills the streaming host process.
2. Runs `stop-display.sh` (tears down the virtual monitor, restores the physical output).

**It deliberately leaves the Plasma session running.** That session is expensive to restart (the password-prompt cost above) and cheap to leave idle (~300MB RAM, 0% CPU) — proven stable across multi-day gaps. If minimizing lingering resource use matters more than avoiding the restart cost, killing the Plasma session too on `stopgames.sh` (and eating the password prompt next time) is a reasonable alternative — a deliberate choice to make explicitly rather than assume.

## `diagnose.sh`

A read-only, full-state snapshot tool — captures session/display/process state in one shot to a timestamped log file, so "did it actually work" can be answered by reading a log instead of guessing from what's visible in the terminal. Covers: environment variables, `loginctl` session state, `systemctl --user` state, Wayland/D-Bus runtime sockets, relevant running processes, `kscreen-doctor` output, GPU state (`nvidia-smi`), recent kernel/user journal errors, and firewall status. Never modifies system state. Safe to run anytime, as often as needed.

Useful pattern: run it once before a change and once after (with different labels), then diff the two log files.

## Client-side wrapper

Not included in this repo (it lives in a private dotfiles setup), but the shape of it: two shell functions on the client machine — `rungames` and `stopgames` — that wake the server (harmless if it's already on), then SSH in and run the corresponding server-side script. The end-to-end flow this project reached: one command on the client → wakes the server → brings up the full stack remotely → opens the streaming client → click the emulator → playing.
