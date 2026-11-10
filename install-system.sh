#!/bin/bash
# Explicit, optional system installation; the normal widget installer stays unprivileged.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

if (( EUID != 0 )); then
  if [[ -t 0 ]]; then
    exec sudo /usr/bin/bash "$PWD/install-system.sh"
  fi
  exec pkexec /usr/bin/bash "$PWD/install-system.sh"
fi

if [[ ! -r /sys/class/power_supply/macsmc-battery/charge_behaviour ]]; then
  echo "The macsmc charging-mode interface is unavailable." >&2
  exit 1
fi

# Stop an earlier installation while its reset helper is still in place.
if /usr/bin/systemctl is-active --quiet apple-silicon-power-guard.service; then
  /usr/bin/systemctl stop apple-silicon-power-guard.service
fi
/usr/bin/install -d -o root -g root -m 0755 /usr/local/lib/apple-silicon-power
/usr/bin/install -o root -g root -m 0755 system/charge-guard.py /usr/local/lib/apple-silicon-power/charge-guard.py
/usr/bin/install -o root -g root -m 0644 system/apple-silicon-power-guard.service /etc/systemd/system/apple-silicon-power-guard.service
/usr/bin/install -o root -g root -m 0755 system/apple-silicon-power-sleep /usr/lib/systemd/system-sleep/apple-silicon-power
/usr/bin/systemctl daemon-reload
/usr/bin/systemctl enable --now apple-silicon-power-guard.service
/usr/bin/systemctl is-active --quiet apple-silicon-power-guard.service
echo "Charge guard installed. Use the panel to enable or disable automatic discharge."
