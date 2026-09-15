#!/usr/bin/env bash
# diagnose.sh — headless game-streaming project
#
# Purpose: capture the fullest possible snapshot of session/display/process
# state in one shot, so a "did it actually work" question can be answered by
# reading a log file instead of guessing from what's visible in the terminal.
#
# Usage:
#   ./diagnose.sh [a short label, e.g. "before" or "after-systemd-run"]
#
# Output: a timestamped, labeled log file under ./notes/logs/
# Also prints a short summary to the terminal so you don't have to open the
# file just to know it ran.
#
# Safe to run repeatedly. Never modifies system state — read-only checks only.

set -uo pipefail

STAMP="$(date '+%Y%m%d-%H%M%S')"
LABEL="${1:-check}"
SCRIPTDIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LOGDIR="$SCRIPTDIR/notes/logs"
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/${STAMP}-${LABEL}.log"

section() {
  {
    echo ""
    echo "======================================================================"
    echo "== $1"
    echo "======================================================================"
  } >>"$LOGFILE"
}

run() {
  # run "description" "command string"
  {
    echo ""
    echo "--- $1 ---"
    echo "\$ $2"
    eval "$2" 2>&1
    echo "(exit code: $?)"
  } >>"$LOGFILE"
}

echo "Running diagnostics at $STAMP, label='$LABEL' ..."
{
  echo "diagnose.sh run"
  echo "Label: $LABEL"
  echo "Timestamp: $(date)"
  echo "Run by: $(whoami)"
} >"$LOGFILE"

# ----------------------------------------------------------------------------
section "BASIC IDENTITY / ENVIRONMENT"
run "hostname"            "hostname"
run "uptime"              "uptime"
run "who am I logged in as, and how" "who -a"
run "current shell"       "echo \$SHELL"
run "relevant env vars"   "env | grep -E '^(XDG_|WAYLAND_|DISPLAY|DBUS_)' | sort"

# ----------------------------------------------------------------------------
section "LOGIN / SEAT / SESSION STATE (loginctl)"
run "all sessions"        "loginctl list-sessions --no-legend"
run "all users"           "loginctl list-users --no-legend"
# Loop over every session id found and dump its full properties.
run "session details (all sessions)" "
  for sid in \$(loginctl list-sessions --no-legend | awk '{print \$1}'); do
    echo \">> session \$sid\"
    loginctl show-session \"\$sid\" 2>&1
    echo
  done
"

# ----------------------------------------------------------------------------
section "SYSTEMD USER SESSION STATE"
run "systemctl --user status (top-level)"   "systemctl --user status --no-pager 2>&1 | head -n 40"
run "systemctl --user failed units"         "systemctl --user --failed --no-pager"
run "systemctl --user list-units (graphical/plasma/kde/sunshine related)" \
    "systemctl --user list-units --all --no-pager 2>&1 | grep -iE 'plasma|kde|kwin|sunshine|graphical' "
run "is plasma-workspace-wayland.target active?" \
    "systemctl --user is-active plasma-workspace-wayland.target"

# ----------------------------------------------------------------------------
section "WAYLAND / DBUS RUNTIME ARTIFACTS"
run "contents of /run/user/\$(id -u)/" "ls -la /run/user/\$(id -u)/ 2>&1"
run "any wayland-* sockets present?"   "find /run/user/\$(id -u)/ -maxdepth 1 -name 'wayland-*' 2>&1"
run "dbus session bus socket present?" "find /run/user/\$(id -u)/ -maxdepth 1 -name 'bus' 2>&1"

# ----------------------------------------------------------------------------
section "PROCESS STATE — anything display/stream related running right now"
run "full process list filtered" \
    "ps -ef | grep -iE 'kwin|plasma|sddm|krfb|kscreen|sunshine|retroarch|Xorg' | grep -v grep"
run "process tree (pstree, if available)" "pstree -a -p 2>&1 || echo 'pstree not installed'"

# ----------------------------------------------------------------------------
section "SCREEN / OUTPUT STATE (kscreen-doctor)"
run "kscreen-doctor -o (raw, may fail if no session)" "kscreen-doctor -o"
run "kscreen-doctor -o (with WAYLAND_DISPLAY=wayland-0 forced)" \
    "WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/run/user/\$(id -u) kscreen-doctor -o"

# ----------------------------------------------------------------------------
section "GPU STATE"
run "nvidia-smi" "nvidia-smi 2>&1"

# ----------------------------------------------------------------------------
section "RECENT LOGS — system journal, errors only, since last boot"
run "journalctl -b -p err (system, this boot, error+)" "journalctl -b -p err --no-pager 2>&1 | tail -n 60"

# ----------------------------------------------------------------------------
section "RECENT LOGS — user journal, since last boot"
run "journalctl -b --user (this boot, all levels, tail)" "journalctl -b --user --no-pager 2>&1 | tail -n 80"

# ----------------------------------------------------------------------------
section "RECENT LOGS — anything mentioning kwin/plasma/sddm in the last 10 min"
run "journalctl grep, last 10 minutes" \
    "journalctl --since '10 minutes ago' --no-pager 2>&1 | grep -iE 'kwin|plasma|sddm|wayland' "

# ----------------------------------------------------------------------------
section "FIREWALL STATE (sanity check — unrelated services shouldn't be exposed)"
run "ufw status verbose" "sudo -n ufw status verbose 2>&1 || echo '(sudo needs a password here — skipped; run manually if needed)'"

# ----------------------------------------------------------------------------
echo ""
echo "Done. Log written to:"
echo "  $LOGFILE"
echo ""
echo "Quick summary:"
echo "  Wayland sockets found: $(find /run/user/$(id -u)/ -maxdepth 1 -name 'wayland-*' 2>/dev/null | wc -l)"
echo "  Relevant processes running: $(ps -ef | grep -iE 'kwin|plasma|sddm|krfb|sunshine' | grep -v grep | wc -l)"
echo "  Failed user systemd units: $(systemctl --user --failed --no-legend 2>/dev/null | wc -l)"
echo ""
echo "Full detail is in the log file above — read that before drawing conclusions."
