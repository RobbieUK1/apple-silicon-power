#!/bin/bash
set -euo pipefail
case "${1:-}" in
  on) action=drain-on ;;
  off) action=drain-off ;;
  *) echo "Usage: set-auto-discharge.sh on|off" >&2; exit 2 ;;
esac
helper=/usr/local/lib/apple-silicon-power/charge-guard.py
[[ -x $helper ]] || { echo "Install the charge guard first." >&2; exit 3; }
if sudo -n "$helper" "$action" 2>/dev/null; then
  exit 0
fi
exec pkexec "$helper" "$action"
