# Getting a Headless Plasma Session to Start Over SSH

## The problem: why a plain SSH command couldn't start Plasma

**Initial assumption:** a Plasma Wayland session could be started with a normal command typed over SSH — `startplasma-wayland`.

**Result:** false. The command fails outright when run from a bare SSH shell.

**Root cause:** a plain SSH connection provides authentication and a remote shell, but nothing more. It carries no display context — no `$DISPLAY` variable, no session manager backing it, no seat assignment. This isn't a Plasma-specific bug — it's the same reason a command like `firefox`, typed into a bare SSH session, won't produce a window. Graphical programs expect to be launched into a session that already has this scaffolding in place, and SSH doesn't provide it.

## Core concept: SSH vs. systemd — two different layers

**SSH** is a remote access protocol. Its entire job is to authenticate a user and hand them an encrypted, remote command shell. It has no concept of "desktop sessions," graphical context, or hardware seats. Once the shell is handed over, SSH's job is essentially done.

**systemd** (specifically `systemd-logind`) is the init system and session manager, active on the machine regardless of whether anyone is remotely connected. Unlike SSH, it has a structured concept of a **session**: it tracks what seat a session is attached to, what type of session it is (tty, X11, Wayland), and builds the environment and device permissions (GPU access, input device access, `XDG_SESSION_TYPE`, etc.) that graphical programs expect to already exist before they'll run.

A normal interactive login — at a physical keyboard, or through a display manager like SDDM — is routed through `systemd-logind`, which constructs the full session context *before* the desktop environment starts. Plasma is written to expect this context to already exist; it doesn't build it for itself. SSH skips this process entirely: it authenticates the user and opens a shell, but never asks `systemd-logind` to construct a session. So when `startplasma-wayland` runs inside that shell, it looks for session infrastructure that was never created, and fails.

## Supporting concept: what a "seat" is

A **seat** (in systemd/logind terminology) represents a physical workstation — the set of hardware (keyboard, mouse, display) a person would sit down at to use a machine directly. Most machines have exactly one, conventionally named `seat0`. The concept exists because a single machine can technically host multiple independent local seats — a niche configuration, which is why systemd formalizes "seat" as an explicit concept rather than assuming one keyboard/one screen/one machine.

On a single-GPU headless server, the machine has exactly one seat — `seat0` — corresponding to hardware that's never physically used (lid closed, headless, no monitor attached). Specifying `XDG_SEAT=seat0` in the fix below tells systemd to attach the new session to that seat, because Plasma expects a seat assignment as part of a legitimate session. This has nothing to do with SSH's network connection; it refers strictly to the (unused) physical hardware on the box itself.

## The fix: `systemd-run`

Found via a KDE Discuss forum thread describing the identical use case, after an initial dead-end search (an Arch Linux forum thread with no resolution posted).

```bash
systemd-run --uid="$(whoami)" -p PAMName=login -E XDG_SEAT=seat0 \
  -E XDG_VTNR=1 -E XDG_SESSION_TYPE=tty -E XDG_SESSION_CLASS=user \
  startplasma-wayland
```

**What it does, conceptually:** rather than trying to run Plasma directly, this instructs systemd to first construct a proper login session — as if the user had logged in at the physical seat — and only then start Plasma inside that freshly-built session. It substitutes, on manual request, for the setup work a display manager would normally perform automatically at boot or physical login.

**Flags, broken down:**
- `--uid="$(whoami)"` — run the session as the current user
- `-p PAMName=login` — use the PAM stack associated with a normal login, so the session is treated as a legitimate authenticated login rather than an ad hoc process
- `-E XDG_SEAT=seat0` — attach the session to the machine's one physical seat
- `-E XDG_VTNR=1` — assign a virtual terminal number
- `-E XDG_SESSION_TYPE=tty` — declare the session type
- `-E XDG_SESSION_CLASS=user` — declare it as a standard user session
- `startplasma-wayland` — the program to run once that session context exists

**Known limitation:** this command requires an interactive password prompt (PolicyKit authentication) every single time it's run — it cannot currently be scripted to run silently over a remote SSH command. This is the single biggest gap standing between "manual" and fully seamless (autologin-at-boot would close it — see `ROADMAP.md`).

## The caveat: a real-world report of partial failure

The same KDE Discuss thread contained a report from a user (`pixeled`) doing the *exact same project* — a remote gaming PC, streaming via Sunshine/Moonlight — who tried this identical command.

Their result: a graphical session *did* start, but it came up empty (no taskbar, nothing directly launchable from it) — and critically, Sunshine itself could not subsequently be started from that same SSH session, hitting the same "can't find a display" problem all over again, one layer up.

**Their follow-up fix**, which resolved the second problem: once a Plasma session is already running, launching a program into it from a *separate* SSH connection only requires one environment variable:

```
WAYLAND_DISPLAY=wayland-0
```

**Why this mattered here specifically:** this detail was checked against the Sunveil reference scripts (see [`03-wayland-pivot-and-full-stack.md`](03-wayland-pivot-and-full-stack.md)), and both `stream-start.sh` and `stream-end.sh` were confirmed to already set `WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"` themselves — meaning this part of the puzzle was already handled by the existing script design.

## Reframing "empty session" as not necessarily a failure

A Plasma session that looks empty (no taskbar, nothing to click) isn't automatically bad news for this use case, the way it would be for someone wanting a normal, usable desktop. The actual bar for success is narrower:

- Does `kscreen-doctor -o` return sane output (confirming the virtual display subsystem is functioning)?
- Can a program actually be launched into the session from a second SSH connection using `WAYLAND_DISPLAY=wayland-0`?

Both are testable, narrow, mechanical checks — distinct from "does this feel like a working desktop."

## A separate, explicitly unresolved risk: virtual vs. physical input

The KDE Discuss thread's bug report described *physical* input devices breaking in this kind of session. That's likely irrelevant on a headless box with no physical keyboard/mouse attached — but a streaming client's controller/keyboard input arrives as **virtual input events injected by the streaming host**, not physical device signals, a mechanically different pathway. These two mechanisms are different enough that the reported bug likely doesn't apply — but this was treated explicitly as an assumption still needing confirmation, not a settled fact, precisely because two earlier "adjacent but not identical" details had already caused real problems in this project (the Xorg CRTC shutdown failure, and an earlier incorrect assumption about the reference project's capture mode).

## Risk assessment: is any of this system-breaking?

**Low risk, by design.** `systemd-run` is a standard systemd feature — spinning up a session and running a program inside it — not a hack that modifies drivers, kernel modules, or system configuration. The expected failure modes are exactly what was observed: the session fails to start, or starts but is unusable. Either way, failure is inert — it doesn't cascade into anything else breaking. Worst case: it doesn't work, and a different approach is tried.

**The caveat:** the earlier Xorg incident wasn't a "feature didn't work" failure — it was a driver-level lockup specific to the interaction between the `ConnectedMonitor`/`CustomEDID` Xorg trick and the NVIDIA driver. Plasma/Wayland uses a different rendering path entirely (KWin as compositor, not raw Xorg), so that specific failure mode isn't automatically expected to recur — but this was also not treated as *proven* impossible, only as not yet triggered by anything tested in the KDE/Wayland approach.

## Diagnostic tooling: reading `ps -ef | grep retroarch`

A useful verification step for confirming a program actually launched inside the invisible session:

```bash
ps -ef | grep retroarch
```

- `ps -ef` lists every running process on the system (`-e` = every process for every user, `-f` = full-format output including owning user, parent PID, start time, and the full command line).
- `| grep retroarch` filters that list down to lines containing "retroarch".

**Known quirk:** this command typically matches its own invocation, since `grep`'s process line contains the search term too. Two ways to avoid the self-match: `grep [r]etroarch` (a regex trick) or `pgrep retroarch` (a purpose-built alternative).

## Summary

**Unchanged:** the overall architecture of the streaming pipeline (see [`03-wayland-pivot-and-full-stack.md`](03-wayland-pivot-and-full-stack.md)).

**Changed, within this specific problem (how the desktop session turns on):**
1. First assumption — a plain `startplasma-wayland` over SSH — confirmed false.
2. Actual fix — `systemd-run` with a specific flag set, sourced from a forum thread describing the identical use case.

**Attached to the fix:** a caveat that the resulting session may appear empty/unusable in the conventional sense, alongside a one-line solution (`WAYLAND_DISPLAY=wayland-0`) for launching programs into that session from a new SSH connection — already built into the Sunveil-derived hook scripts.

**Explicitly still open at the time of writing:** whether the "empty session" is fully sufficient (narrower success bar defined above); whether the streaming host's virtual input injection is meaningfully different from the physical-input-device bug reported in the same forum thread; whether any Wayland/KWin-specific unkillable-state failure mode exists, analogous to the Xorg/NVIDIA CRTC lockup — nothing so far points toward one, but it hasn't been proven impossible either.
