#!/usr/bin/env bash
# stopgames.sh — headless game-streaming project
#
# Reverses rungames.sh, partially by design:
#   - Stops Sunshine
#   - Tears down the virtual display (stop-display.sh)
#   - Deliberately LEAVES the Plasma session running — it's cheap to keep
#     alive (proven stable for days at a time) and restarting it is the one
#     step that needs a password prompt, so there's no benefit to killing it
#     every time.
#
# If you genuinely want the session gone too (e.g. before a reboot anyway),
# that's a separate, explicit step — not part of normal day-to-day teardown.
# See ROADMAP.md for the tradeoff this represents.

set -uo pipefail

SCRIPTDIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LOG="$SCRIPTDIR/rungames.log"

log() { echo "[$(date '+%F %T')] $*" >>"$LOG"; }

export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

echo "" >>"$LOG"
log "=== stopgames starting ==="

if pgrep -u "$(whoami)" -x sunshine >/dev/null 2>&1; then
  pkill -u "$(whoami)" -x sunshine
  log "Stopped Sunshine"
else
  log "Sunshine was not running"
fi

"$SCRIPTDIR/stop-display.sh" | tee -a "$LOG"

log "=== stopgames: done (Plasma session left running) ==="
echo ""
echo "Sunshine and the virtual display are stopped."
echo "The Plasma session is left running for next time."
