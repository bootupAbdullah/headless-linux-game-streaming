#!/usr/bin/env bash
# rungames.sh — headless game-streaming project
#
# Brings up the full stack in order, skipping any layer that's already up:
#   1. Plasma Wayland session
#   2. Virtual display (start-display.sh)
#   3. Sunshine
#
# After this runs successfully, connecting via Moonlight and clicking
# your streaming application (e.g. RetroArch) is the only remaining step.
#
# KNOWN LIMITATION: starting the Plasma session (layer 1) requires an
# interactive sudo/PolicyKit password prompt. If run over SSH, use
# `ssh -t` so that prompt can actually be answered. This goes away once
# autologin-at-boot is set up (see ROADMAP.md) — at that point layer 1 will
# already be running after every boot and this script will just skip it.

set -uo pipefail

SCRIPTDIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LOG="$SCRIPTDIR/rungames.log"

# CUSTOMIZE: must match the VM_NAME used in start-display.sh
VM_NAME="myserver-vm"

log() { echo "[$(date '+%F %T')] $*" >>"$LOG"; }

export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"

echo "" >>"$LOG"
log "=== rungames starting ==="

# ---------------------------------------------------------------------------
# Layer 1 — Plasma Wayland session
# ---------------------------------------------------------------------------
if pgrep -u "$(whoami)" -f kwin_wayland >/dev/null 2>&1; then
  log "Layer 1 (Plasma session): already running, skipping"
else
  log "Layer 1 (Plasma session): not running, starting..."
  echo "Starting Plasma session — you may be prompted for your password."
  systemd-run --uid="$(whoami)" -p PAMName=login -E XDG_SEAT=seat0 \
    -E XDG_VTNR=1 -E XDG_SESSION_TYPE=tty -E XDG_SESSION_CLASS=user \
    startplasma-wayland

  echo "Waiting for session to come up..."
  ready=false
  for _ in $(seq 1 40); do
    if [ -S "$XDG_RUNTIME_DIR/wayland-0" ]; then
      ready=true
      break
    fi
    sleep 0.5
  done

  if [ "$ready" = true ]; then
    log "Layer 1: wayland-0 socket confirmed present"
  else
    log "Layer 1: ERROR — wayland-0 socket never appeared"
    echo "ERROR: Plasma session failed to start. Check $LOG"
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Layer 2 — Virtual display
# ---------------------------------------------------------------------------
if kscreen-doctor -o 2>/dev/null | grep -q "Virtual-$VM_NAME"; then
  log "Layer 2 (virtual display): already up, skipping"
else
  log "Layer 2 (virtual display): not up, starting..."
  "$SCRIPTDIR/start-display.sh" | tee -a "$LOG"
fi

# ---------------------------------------------------------------------------
# Layer 3 — Sunshine
# ---------------------------------------------------------------------------
if pgrep -u "$(whoami)" -x sunshine >/dev/null 2>&1; then
  log "Layer 3 (Sunshine): already running, skipping"
else
  log "Layer 3 (Sunshine): not running, starting detached..."
  setsid sunshine >>"$SCRIPTDIR/sunshine-rungames.log" 2>&1 < /dev/null &
  disown
  sleep 2
  if pgrep -u "$(whoami)" -x sunshine >/dev/null 2>&1; then
    log "Layer 3: Sunshine confirmed running"
  else
    log "Layer 3: ERROR — Sunshine did not start"
    echo "ERROR: Sunshine failed to start. Check $SCRIPTDIR/sunshine-rungames.log"
    exit 1
  fi
fi

log "=== rungames: all layers up ==="
echo ""
echo "All set. Session, display, and Sunshine are running."
echo "Open Moonlight and click your streaming application."
