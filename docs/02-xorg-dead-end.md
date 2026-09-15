# The Xorg Dead End: An Unkillable NVIDIA Shutdown Hang

**If a search brought you here, this is probably the page you want.** This documents a specific, reproducible failure: creating a fake/virtual monitor on an NVIDIA GPU via Xorg's `ConnectedMonitor` + a synthetic EDID starts cleanly, then makes the entire machine unrecoverable on shutdown.

## The goal, for context

Stream a game running on a headless server to another machine, over the network:

**Xorg** (creates a fake screen for the game to draw on) → **RetroArch** (runs the emulator, draws frames onto that screen) → **Sunshine** (captures the screen, compresses it, sends it over the network) → **Moonlight** (client — displays the stream, sends input back)

This page covers only the first piece: getting Xorg to create, and then cleanly tear down, a fake display. That turned out to be a much deeper problem than expected — deep enough that it forced a full architecture change (see [`03-wayland-pivot-and-full-stack.md`](03-wayland-pivot-and-full-stack.md)).

## Hardware / driver identification

| Item | Value |
|---|---|
| GPU | NVIDIA Quadro P600, 4GB VRAM |
| GPU architecture | **Pascal** (GP107 chip) — see the correction note in [`01-hardware-and-driver.md`](01-hardware-and-driver.md); early notes from this project mislabeled it Maxwell |
| Driver | 580.173.02 — Legacy branch (the newest driver that still supports this GPU generation) |

This Pascal + Legacy-580.x pairing is old and narrow enough that few other people online appear to have hit and solved this specific combination — which is the entire reason this page exists.

## The setup that triggers the bug

With no physical monitor ever attached, two Xorg settings were used to convince the NVIDIA driver one was connected:

1. **`ConnectedMonitor "DFP-0"`** — tells the driver to treat an output port as if a real monitor is plugged in.
2. **A synthetic EDID file** — a small generated binary (128 bytes) supplying fake monitor capability data (resolution/timing info a real monitor would normally provide automatically), referenced via `Option "CustomEDID" "DFP-0:/path/to/virtual-display.bin"`.

Relevant `xorg.conf` (`Device` section):

```
Section "Device"
    Identifier "Card0"
    Driver "nvidia"
    VendorName "NVIDIA Corporation"
    BusID "PCI:1:0:0"
    Option "MetaModes" "1920x1080"
    Option "ConnectedMonitor" "DFP-0"
    Option "CustomEDID" "DFP-0:/path/to/virtual-display.bin"
    Option "ModeValidation" "NoDFPNativeResolutionCheck,NoVirtualSizeCheck,NoMaxPClkCheck,NoHorizSyncCheck,NoVertRefreshCheck,NoWidthAlignmentCheck"
EndSection
```

Both settings only need to be convincing enough for **startup** — and they are. Xorg starts cleanly every time: the fake display connects, a 1920×1080 mode gets set, no `(EE)` errors in the log.

## The bug: stuck on shutdown, not startup

**Startup always works.** The problem is entirely in tearing the fake display back down — whether by killing the Xorg process, running `reboot`, or running `shutdown now`. All three were tested. All three hang identically.

### What "hangs" actually means here

- The stuck Xorg process becomes completely unkillable — confirmed via repeated `kill -9`, `pkill -9`, and process-group kill attempts, all failing.
- `/proc/<pid>/status` showed `SIGKILL` as *pending* (`SigPnd` bit set) but never delivered — the technical signature of a process parked in **uninterruptible sleep** inside a kernel-mode operation. This state cannot be interrupted by any signal, by design: interrupting a driver mid-hardware-operation risks leaving actual hardware in an inconsistent state.
- One CPU core pegs at ~97–100% while stuck. The rest of the system is unaffected while this is happening.
- A full reboot/shutdown attempted while this is occurring hangs the **entire machine**, not just Xorg. Recovery required a hard power-off (holding the power button) on every occurrence — no software-level recovery path worked.

### Root cause, isolated via two pieces of direct evidence

**1. Kernel error log** (captured via a photo of the physical screen during a hung shutdown, since the machine was too stuck to retrieve it any other way):

```
nvidia 0000:01:00.0: [drm] *ERROR* Disabling all crtc's during unload failed with -22
task poweroff:XXXX blocked on a semaphore likely last held by task Xorg:XXXX
```

- `-22` is Linux's `EINVAL` ("invalid argument") error code.
- This says the driver tried to disable the CRTCs (the internal GPU hardware paths that drive a display output) as part of shutdown, and rejected its own request as invalid.
- It also spells out the exact causal chain: `poweroff` was blocked waiting on a lock held by Xorg, and Xorg never released it because it never got past the failed CRTC-disable step. **This is why the entire shutdown hangs, not just Xorg.**

**2. Kernel stack trace**, read directly via `/proc/<pid>/stack` (`strace` itself got stuck trying to attach to the process — same underlying problem):

```
nvkms_yield → _nv000172kms → _nv000386kms → _nv002730kms → _nv000586kms →
_nv000588kms → _nv003234kms → nvKmsIoctl → nvkms_unlocked_ioctl → ioctl syscall
```

Checked twice, several seconds apart — identical both times, confirming the process isn't retrying or making progress. It's parked at one exact instruction inside `nvkms_yield`, deep inside NVIDIA's own closed-source kernel module (`nvidia-modeset`).

### What a CRTC is, for reference

Short for "CRT Controller" (a legacy name, unrelated to CRT monitors specifically). It's the internal GPU circuit/logic responsible for continuously feeding pixel data to one specific display output at the correct timing and resolution. "Disabling" a CRTC is the normal, routine handshake that happens whenever a display is no longer needed — stop the timing signals, release the memory buffer, mark the hardware path free again.

### Why Xorg (not the driver) shows up as the "stuck" process

Xorg doesn't manipulate GPU hardware directly — it makes a request into the NVIDIA driver (an `ioctl` call) and waits for it to return. On shutdown, one of Xorg's last steps is asking the driver to disable the CRTCs it was using. That request is what gets stuck inside the driver's own code — and because Xorg is paused inside that same call, waiting for it to return, Xorg itself appears hung in `ps aux`, even though the actual malfunctioning code is inside `nvidia-modeset`, not Xorg.

### Why this looks like a genuine driver bug, not a config mistake

- Not fixable from `xorg.conf` — the failure is in the driver's internal shutdown logic, a layer no Xorg config option reaches.
- Not a signal-delivery issue — `kill -9` failing is a symptom of *where* the code is stuck (uninterruptible kernel-mode execution), not evidence of a fixable process-handling bug.
- Not something a container or process-isolation approach can work around — containers isolate processes, not access to shared kernel drivers. A containerized Xorg would still call into the exact same shared NVIDIA kernel module and hit the same stuck code.

### Working theory on *why* the bug exists (unconfirmed — driver internals aren't visible)

A real, physically-connected monitor naturally satisfies certain handshake signals / internal state flags during connection that a `ConnectedMonitor`-forced fake connector apparently never fully replicates. The driver's shutdown logic appears to check for that state, doesn't find it, and — instead of failing gracefully — spins forever waiting for a condition that can never become true. A well-designed driver could detect an invalid teardown state and fail cleanly (log an error, release the CRTC anyway, move on) instead of hanging the whole shutdown sequence. Plausibly explained by Legacy driver branches receiving far less edge-case testing, and this specific use case (fake display created *and fully torn down*, for headless streaming) being a relatively newer, narrower pattern.

## Fixes attempted

| Attempt | What it targeted | Result |
|---|---|---|
| Synthetic EDID file (`CustomEDID`) | A separate cosmetic warning (`cannot compute DPI from EDID`) | Fixed the DPI warning. **Did not fix the shutdown hang** — same CRTC error reproduced identically afterward. |
| `/etc/modprobe.d/nvidia-pm.conf` (`NVreg_EnableGpuFirmware=0`, `NVreg_DynamicPowerManagement=0x02`) | GPU firmware offload / dynamic power management | Applied, `update-initramfs -u` run, machine rebooted. Effect inconclusive on this attempt. |
| `shutdown now` (vs. `reboot`) | Whether a different shutdown command avoids the same code path | Hung identically — both commands converge on the same underlying teardown sequence. |

## Options considered

1. Post to a Linux hardware/driver forum asking specifically about this GPU/driver combination — see the post below.
2. Re-verify whether the power-management modprobe fix actually loaded.
3. A more complete/convincing virtual-display emulation than `ConnectedMonitor` + basic EDID.
4. A kernel-parameter/DRM-level approach (`drm.edid_firmware`, `video=`) instead of `nvidia-modeset`'s `ConnectedMonitor`.
5. A different driver branch that might not have this specific bug.
6. A physical dummy HDMI/DisplayPort plug — sidesteps the entire bug class, since it's a real electrical connection rather than software-level fakery.
7. Accept the bug and build a fast recovery workflow around it (pre-enabled Magic SysRq for a remote forced reboot, if the hang recurs).

## What was actually posted, and the resolution

The question was posted publicly (Linux hardware/support forum), asking whether anyone had gotten a `ConnectedMonitor`-forced display to start **and shut down cleanly** on this GPU/driver combination, or whether this is a known limitation:

> **Is it possible to run a fake/virtual monitor on this NVIDIA driver (Quadro P600, Legacy driver 580.173.02) without it hanging on shutdown?**
>
> I have a headless Ubuntu server (no monitor plugged in) with an NVIDIA Quadro P600 using the Legacy 580.173.02 driver.
>
> I added `ConnectedMonitor` to my xorg.conf to make the driver think a monitor is plugged in. I also created a Python script to generate a fake EDID binary and pointed to it with the `CustomEDID` option to satisfy the driver's need for display info.
>
> Xorg starts up fine with this setup, no errors. But on teardown (killing Xorg, rebooting, shutting down) there's a kernel level command that gets stuck and never completes. On shutdown this shows in the logs:
>
> ```
> nvidia: [drm] *ERROR* Disabling all crtc's during unload failed with -22
> ```
>
> The process becomes completely unkillable at that point, doesn't respond to `kill -9`, and the only way out has been a hard power off.
>
> Has anyone actually done this successfully, a fake/virtual monitor on this GPU/driver combo that shuts down cleanly? Or is this a known limitation? Just trying to find out if it's possible at all before I keep chasing it.

**The answer, in the end: this specific path (Xorg + `ConnectedMonitor` + fake EDID, on this GPU/driver combination) was abandoned rather than fixed.** No configuration-level solution was found. What actually resolved the project wasn't a fix for Xorg — it was switching to a different display mechanism entirely, one with real, officially-supported headless-display capability rather than a forced-fake-monitor trick:

> **Edit: It can be done.**
> Ubuntu 26.04 LTS (Wayland/KDE/KWin → PipeWire → Sunshine) → Tailscale → \[client machine\] (Avahi → Moonlight) → RetroArch/Snes9x → confirmed working, live, with audio.

That pivot — why Wayland/KWin succeeds where Xorg couldn't, and the full architecture that resulted — is documented in [`03-wayland-pivot-and-full-stack.md`](03-wayland-pivot-and-full-stack.md).

## Safety practices established along the way

- **Wake-on-LAN** confirmed working before any risky test — important caveat: WoL only powers a machine on from a genuinely *off* state. It does not help if the machine is hung-but-still-powered (the actual failure mode here); there is no remote way to power off a machine stuck in this hang.
- **Magic SysRq** (`echo 1 | sudo tee /proc/sys/kernel/sysrq`) identified as the best available remote fallback if the hang recurs — bypasses the normal shutdown sequence by talking directly to the kernel. Not persistent across reboots.
- A stopped (`T` state) Xorg process from shell job-control suspension is a different, benign issue, not the real hang — distinguishable by CPU usage (0% vs. the real hang's ~100%).
