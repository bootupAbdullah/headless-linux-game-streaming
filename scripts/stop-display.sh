#!/usr/bin/env bash
# stop-display.sh — headless game-streaming project
# Companion to start-display.sh. Reverses everything it did: restores the
# physical output, kills the virtual monitor process, restores the
# original primary display.
#
# Safe to run even if start-display.sh failed partway — it only acts on
# state it can actually find, and warns rather than errors if state is
# missing.

set -uo pipefail

SCRIPTDIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LOG="$SCRIPTDIR/hook.log"
STATE="$SCRIPTDIR/state"

# CUSTOMIZE: must match the VM_NAME used in start-display.sh
VM_NAME="myserver-vm"

log() { echo "[$(date '+%F %T')] stop:  $*" >>"$LOG"; }

export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"

# --- re-enable every output that was on before start-display.sh ran -----------
if [ -f "$STATE/enabled_before" ]; then
  enable_args=()
  while read -r name; do
    [ -z "$name" ] && continue
    enable_args+=("output.$name.enable")
  done <"$STATE/enabled_before"
  if [ "${#enable_args[@]}" -gt 0 ]; then
    kscreen-doctor "${enable_args[@]}" >>"$LOG" 2>&1 \
      && log "re-enabled: ${enable_args[*]}" \
      || log "WARN: failed to re-enable some outputs"
  fi
else
  log "WARN: no enabled_before state found; leaving displays as-is"
  echo "Note: no prior state found — nothing to restore. If start-display.sh"
  echo "was never run in this session, that's expected."
fi

# --- kill the virtual monitor ---------------------------------------------------
if [ -f "$STATE/vm.pid" ]; then
  VMPID="$(cat "$STATE/vm.pid")"
  if kill "$VMPID" 2>/dev/null; then
    log "killed krfb-virtualmonitor pid=$VMPID"
  else
    pkill -f "krfb-virtualmonitor.*$VM_NAME" 2>/dev/null && log "swept stray krfb (pid $VMPID gone)"
  fi
  rm -f "$STATE/vm.pid"
else
  pkill -f "krfb-virtualmonitor.*$VM_NAME" 2>/dev/null && log "swept krfb (no pidfile)"
fi

# --- restore the true primary that was set before start-display.sh -------------
PRIMARY=""
[ -f "$STATE/primary_before" ] && PRIMARY="$(cat "$STATE/primary_before")"
[ -z "$PRIMARY" ] && [ -f "$STATE/enabled_before" ] && PRIMARY="$(head -n1 "$STATE/enabled_before")"
if [ -n "$PRIMARY" ]; then
  kscreen-doctor "output.$PRIMARY.primary" >>"$LOG" 2>&1 \
    && log "restored primary to $PRIMARY" \
    || log "WARN: failed to restore primary $PRIMARY"
fi

log "done"
echo "Display teardown complete. Check $LOG for details."
exit 0
