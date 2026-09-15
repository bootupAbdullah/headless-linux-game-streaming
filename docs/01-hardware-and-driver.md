# Hardware, OS, and the GPU/Driver Situation

## Hardware

| Item | Value |
|---|---|
| Machine | Dell Precision 3530 Mobile Workstation (a hand-me-down laptop, repurposed as a headless server) |
| CPU | Intel i5-8400H, 6 cores |
| RAM | 16GB |
| Storage | 256GB NVMe SSD |
| GPU | NVIDIA Quadro P600, 4GB VRAM |
| Battery | Physically removed — the machine runs AC-only, 24/7, no portability need |

Before any software work began, the hardware itself was validated: stress-tested under full 6-core load, disk health checked via SMART (passed, healthy wear level), and confirmed capable of sustained, unattended operation. The machine has no monitor, keyboard, or mouse ever attached — everything from here on happens headless, over the network.

## A correction worth stating plainly

Early in this project the GPU was mislabeled as **Maxwell** generation. It is not — it's **Pascal** (the GP107 chip). Maxwell is NVIDIA's M-series Quadro line; Pascal is the P-series (as in "Quadro **P**600"). This correction matters because the two generations sit on different driver support timelines, and any conclusion about driver ceilings only holds if the generation is right. Everywhere below uses the corrected label; if you find "Maxwell" anywhere in older notes tied to this project, it's the same mistake.

## Operating System

Ubuntu 26.04 LTS, clean install, accessed exclusively over SSH.

## GPU Driver

| Item | Value |
|---|---|
| Driver | 580.173.02 — **Legacy branch** |
| CUDA | 13.0 |
| VRAM confirmed available | 4096 MiB |

**Why "Legacy" and why that matters:** NVIDIA ended feature-branch driver support for the Maxwell/Pascal/Volta generations starting with driver 590 (Dec 2025). Driver 580.x is the last full-feature branch this GPU will ever receive — security-only patches continue through 2028, but no new features. Driver 610+ does not support this GPU at all.

**A driver-install gotcha, if you're setting up a similar machine:** an automated install script (in this case, Ollama's) pulled the *newest* available NVIDIA driver (610.x) by default, which silently dropped support for this GPU generation and caused a boot-time CUDA probe error loop (harmless, ~53 seconds at boot, but noisy and confusing until diagnosed). The fix:

```bash
sudo apt purge '*nvidia*'
sudo apt install nvidia-driver-580
```

Confirmed working via `nvidia-smi` afterward.

## The permanent ceiling: no hardware video encoding

This is the single most important hardware fact for anyone attempting a similar streaming build on an older NVIDIA GPU.

NVIDIA's dedicated hardware video encoder (NVENC) is present on this card, but only supports encoder API version up to 13.0. Sunshine (the streaming host used in this build — see `docs/03-wayland-pivot-and-full-stack.md`) requires API 13.1+. There is no driver upgrade path that both supports this GPU *and* provides a newer NVENC API — newer drivers simply drop the GPU generation entirely.

**This is not a bug to chase.** It's a real, permanent hardware/vendor limit. The correct, permanent answer is software encoding (`libx264`, done on the CPU) — confirmed in real testing to use roughly 1 of 6 CPU cores during actual gameplay streaming, well within this machine's proven headroom.

Where the GPU actually is and isn't involved across the whole pipeline is broken down layer-by-layer in [`03-wayland-pivot-and-full-stack.md`](03-wayland-pivot-and-full-stack.md).
