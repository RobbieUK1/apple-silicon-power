#!/bin/bash
# Change the Apple Silicon charge limit through Omarchy's supported helper.
# The shell runs without a terminal, so fall back to the desktop's polkit
# agent when sudo credentials are not already cached.
set -euo pipefail

limit="${1:-}"
case "$limit" in
  80 | 100) ;;
  *)
    echo "Unsupported charge limit: $limit" >&2
    exit 2
    ;;
esac

helper="/usr/bin/omarchy-battery-charge-limit"
if [[ ! -x $helper ]]; then
  echo "omarchy-battery-charge-limit is not installed." >&2
  exit 3
fi

if sudo -n "$helper" "$limit" 2>/dev/null; then
  exit 0
fi

exec pkexec "$helper" "$limit"
