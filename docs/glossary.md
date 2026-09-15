# Technical Glossary

Plain-language reference for terms used throughout this repo.

## Display system basics

**Monitor / Display** — the physical screen a computer draws images onto. A headless server has none attached — the whole point of this project is to trick, or properly construct, a "fake" one.

**Headless** — a computer with no monitor, keyboard, or mouse physically attached, managed entirely over the network (SSH).

**EDID (Extended Display Identification Data)** — a small block of data a real monitor sends to the GPU describing its capabilities: supported resolutions, refresh rates, physical size. Without it, a driver has to guess or use defaults.

**Connector** — the physical port on a GPU where a monitor would plug in (HDMI, DisplayPort, etc.). Each has an internal driver name, like `DFP-0` or `DP-0`.

**CRTC (CRT Controller — legacy name, still used)** — the internal hardware/driver pathway responsible for generating the actual video signal for a display output. "Disabling all CRTCs" is what a driver does when shutting down a display — the exact step that fails in the bug documented in `02-xorg-dead-end.md`.

**DPI (Dots Per Inch)** — how densely pixels are packed on a screen; used for scaling text/UI elements correctly. Normally calculated from a monitor's real EDID data.

**Framebuffer** — a block of memory representing the current pixel data of a screen. A display server creates and manages this; other programs draw into it.

## The old approach: X11 / Xorg

**X11** — a decades-old (1980s) protocol/system for managing how programs draw to a screen.

**Xorg** — the specific, most common program that implements X11 on Linux — both the "rulebook follower" and the actual display-drawing engine, combined into one program.

**xorg.conf** — the configuration file Xorg reads at startup, controlling which driver to use, display options, and (in this project's abandoned approach) the fake-monitor tricks.

**ConnectedMonitor** (NVIDIA driver option) — an Xorg config setting that forces the NVIDIA driver to report a monitor as physically attached to a connector, even when nothing is plugged in.

**CustomEDID** (NVIDIA driver option) — an Xorg config setting that supplies a real (or synthetic/fake) EDID file for a connector, instead of leaving the driver with no display data at all.

**TwinView** — an older NVIDIA-specific Xorg option for managing multiple displays as one combined virtual screen. Largely superseded by RandR.

**RandR** — a more modern X11 extension for handling display configuration.

## The new approach: Wayland / compositors

**Wayland** — a modern *protocol* for how screen-drawing should work, the intended long-term replacement for X11/Xorg. Not a running program itself — a set of rules other software follows.

**Compositor** — the actual piece of software that follows the Wayland rulebook: combining windows, backgrounds, and cursors into a final image, and talking directly to the GPU driver. The direct equivalent of the role Xorg played.

**Desktop Environment (DE)** — a complete, packaged user interface experience. GNOME and KDE Plasma are both examples.

**Mutter** — the compositor used internally by GNOME.

**KDE Plasma** — a desktop environment, an alternative to GNOME.

**KWin** — the compositor used internally by KDE Plasma, playing the same role as Mutter.

**Headless virtual monitor (Wayland feature)** — a genuine, officially-supported feature in modern compositors (confirmed in GNOME's Mutter since 2021) allowing a virtual/fake display to be created properly, as an intended use case — unlike the Xorg `ConnectedMonitor` trick, which was never an officially supported technique.

## The game/streaming pipeline

**RetroArch** — the emulator front-end software. Runs the actual game logic and renders each frame into the display server's framebuffer.

**Sunshine** — the streaming host software. Captures rendered frames, encodes them, and streams them over the network; also handles receiving controller/keyboard input back from the client.

**kmsgrab** — Sunshine's default screen-capture method on Linux. Limitation: it can only capture *physical* monitors, not virtual/headless ones.

**Portal-based capture** — an alternative screen-capture method (via the desktop environment's built-in screen-sharing system) that Sunshine can use instead of `kmsgrab` — necessary for capturing a virtual/headless display under Wayland.

**Moonlight** — the client app that connects to Sunshine, receives the video stream, displays it, and sends controller/keyboard input back.

**NVENC** — NVIDIA's dedicated hardware video encoder circuit on the GPU, separate from the regular rendering/compute cores.

## Driver / kernel concepts

**Driver** — the software layer that lets the operating system communicate with a specific piece of hardware.

**Driver branch (e.g. "Legacy 580")** — NVIDIA releases different driver version lines for different GPU hardware generations. Newer GPUs get the latest branch; older ones are supported by a "Legacy" branch with limited ongoing updates.

**Pascal** — the codename for one NVIDIA GPU hardware architecture generation (NVIDIA names generations after scientists). Not to be confused with Maxwell, an earlier generation — see the correction note in `01-hardware-and-driver.md`.

**Kernel module** — a piece of driver code loaded directly into the Linux kernel to enable hardware support. `nvidia`, `nvidia_modeset`, and `nvidia_drm` are all kernel modules loaded for NVIDIA GPU support.

**modprobe** — the Linux command/system used to load, unload, and configure kernel modules and their options.

**initramfs** — a small, temporary filesystem loaded very early in the Linux boot process. Kernel module settings sometimes need to be rebuilt into this file (`update-initramfs`) to take effect on the next boot.

**GRUB** — the bootloader — the first software that runs when the machine powers on, responsible for starting the Linux kernel.

**Kernel parameter** — a setting passed to the Linux kernel at boot time (via GRUB), affecting low-level behavior before the main operating system starts.

**SIGTERM** — a "please shut down" signal sent to a running program, asking it to close itself gracefully. Programs can delay, ignore, or customize their response.

**SIGKILL (`kill -9`)** — a forceful "terminate immediately" signal. Normally cannot be ignored or blocked by a program.

**Semaphore** — a kind of lock used by the OS to coordinate access between different programs/processes.

**EINVAL (`-22`)** — a standard Linux error code meaning "invalid argument" — the system rejected a request as fundamentally malformed or not allowed, rather than failing due to a hardware problem.

**Kernel stack trace** — a snapshot of exactly which internal functions a stuck or running process is currently executing, layer by layer. Used to pinpoint precisely where in a driver's code a process is stuck.

## Networking / server management

**SSH** — the standard secure method of remotely accessing and controlling a Linux server's command line over a network.

**Mesh VPN** — a private virtual network connecting a specific set of devices directly to each other, letting a server be reached securely from anywhere without exposing it to the public internet.

**Firewall** — software that controls which network ports/traffic are allowed in or out of a machine.

**systemd** — the core system/service manager on modern Linux distributions, responsible for starting services, managing processes, and handling shutdown/boot sequences.

**journalctl** — the command used to read system/kernel logs managed by systemd.

**dmesg / kernel log** — the running log of messages produced directly by the Linux kernel.
