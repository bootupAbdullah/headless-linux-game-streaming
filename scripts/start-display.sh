#!/usr/bin/env bash
# start-display.sh — headless game-streaming project
# Adapted from Sunveil (github.com/ImStillBlue/sunshine-virtual-display),
# originally a Sunshine "stream-start" hook triggered automatically on
# client connect. This version is run manually, by hand, over SSH.
#
# What it does:
#   1. Records which physical outputs are currently on (so they can be
#      restored later by stop-display.sh)
#   2. Launches krfb-virtualmonitor to create a virtual display
#   3. Sets that virtual display as the active/primary output
#   4. Disables the real physical output (eDP-1 — adjust to your panel's name)
#
# Resolution/fps are hardcoded for now (1920x1080@60) — adjust to match
# your own physical panel's native mode, or make configurable if you need
# per-client resolution matching (see Sunveil's own approach for that).
#
# Everything logged to <project>/scripts/hook.log for debugging.
# State (what to restore) saved under <project>/scripts/state/.

set -uo pipefail

SCRIPTDIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LOG="$SCRIPTDIR/hook.log"
STATE="$SCRIPTDIR/state"
mkdir -p "$STATE"

# CUSTOMIZE: pick a short label for your own machine/setup.
VM_NAME="myserver-vm"
VMOUT="Virtual-$VM_NAME"
DISABLE_PHYSICAL=true
W=1920
H=1080
FPS=60
FPS_MHZ=$(( FPS * 1000 ))
# CHANGE THIS before any real use — visible via `ps -ef` on this host (see
# the "known quirks" note in this project's docs re: krfb-virtualmonitor
# having no file/stdin password option).
VNC_PASSWORD="changeme"
VNC_PORT=5905

log() { echo "[$(date '+%F %T')] start: $*" >>"$LOG"; }

# ensure this script can talk to the Plasma session no matter which SSH
# terminal it's run from — this is the "every new session needs this set"
# gotcha discovered earlier (see docs/04-session-startup-systemd-run.md).
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"

log "starting, target ${W}x${H}@${FPS}, DISABLE_PHYSICAL=$DISABLE_PHYSICAL"

# strip ANSI color codes kscreen-doctor -o emits, for reliable parsing
kso() { kscreen-doctor -o 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g'; }

# --- record physical outputs enabled right now (for teardown later) -----------
snap="$(kso)"
awk '/^Output:/{name=$3} /enabled/{print name}' <<<"$snap" | sort -u >"$STATE/enabled_before"
awk '/^Output:/{name=$3} /priority 1$/{print name; exit}' <<<"$snap" >"$STATE/primary_before"
log "enabled before: $(tr '\n' ' ' <"$STATE/enabled_before")"
log "primary before: $(cat "$STATE/primary_before" 2>/dev/null)"

# clean up any stray virtual monitor from a previous crashed/incomplete run
pkill -f "krfb-virtualmonitor.*$VM_NAME" 2>/dev/null && { log "swept stale krfb"; sleep 0.5; }

before="$(kso | awk '/^Output:/{print $3}' | sort)"

# --- launch the virtual monitor (detached; must keep running) -----------------
setsid krfb-virtualmonitor \
  --resolution "${W}x${H}" \
  --name "$VM_NAME" \
  --password "$VNC_PASSWORD" \
  --port "$VNC_PORT" \
  >>"$LOG" 2>&1 &
VMPID=$!
echo "$VMPID" >"$STATE/vm.pid"
log "launched krfb-virtualmonitor pid=$VMPID (${W}x${H})"

# --- wait for the virtual output to appear -------------------------------------
NEWOUT=""
for _ in $(seq 1 40); do
  sleep 0.3
  now="$(kso | awk '/^Output:/{print $3}')"
  if grep -qx "$VMOUT" <<<"$now"; then
    NEWOUT="$VMOUT"; break
  fi
  cand="$(comm -13 <(echo "$before") <(echo "$now" | sort) | head -n1)"
  [ -n "$cand" ] && { NEWOUT="$cand"; break; }
done

if [ -z "$NEWOUT" ]; then
  log "ERROR: virtual output never appeared; NOT touching physical output (failsafe)"
  echo "ERROR: virtual display never appeared. Check $LOG for details."
  exit 1
fi
echo "$NEWOUT" >"$STATE/vm.output"
log "virtual output: $NEWOUT"

# --- pin it to the exact mode ---------------------------------------------------
kscreen-doctor "output.$NEWOUT.addCustomMode.${W}.${H}.${FPS_MHZ}.full" >>"$LOG" 2>&1 \
  && log "added custom mode ${W}x${H}@${FPS}" || log "custom-mode add skipped (may already exist)"
if   kscreen-doctor "output.$NEWOUT.mode.${W}x${H}@${FPS}" >>"$LOG" 2>&1; then log "mode -> ${W}x${H}@${FPS}"
elif kscreen-doctor "output.$NEWOUT.mode.${W}x${H}"        >>"$LOG" 2>&1; then log "mode -> ${W}x${H} (default fps)"
else log "mode set failed; keeping compositor default"; fi

# --- make the virtual output active & primary -----------------------------------
kscreen-doctor "output.$NEWOUT.enable" "output.$NEWOUT.primary" >>"$LOG" 2>&1

# --- optionally disable the physical output (eDP-1) -----------------------------
if [ "$DISABLE_PHYSICAL" = "true" ]; then
  disable_args=()
  while read -r name; do
    [ -z "$name" ] && continue
    [ "$name" = "$NEWOUT" ] && continue
    disable_args+=("output.$name.disable")
  done <"$STATE/enabled_before"

  if [ "${#disable_args[@]}" -gt 0 ]; then
    kscreen-doctor "${disable_args[@]}" >>"$LOG" 2>&1 \
      && log "disabled physical: ${disable_args[*]}" \
      || log "WARN: failed to disable some physical outputs"
  fi
else
  log "coexist mode: leaving physical output on"
fi

log "done"
echo "Virtual display '$VM_NAME' is up on output $NEWOUT (${W}x${H}@${FPS})."
echo "VNC listening on port $VNC_PORT (password set in script — change before real use)."
exit 0
