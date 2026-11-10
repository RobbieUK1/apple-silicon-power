#!/usr/bin/python3 -I
"""Optional macsmc charge enforcement, independent of the desktop widget."""
import json
import os
from pathlib import Path
import signal
import sys
import time

BATTERY = Path("/sys/class/power_supply/macsmc-battery")
AC = Path("/sys/class/power_supply/macsmc-ac/online")
CONFIG = Path("/etc/apple-silicon-power.json")
STATUS = Path("/run/apple-silicon-power/status.json")


def selected_behaviour(text):
    return next((word[1:-1] for word in text.split()
                 if word.startswith("[") and word.endswith("]")), None)


def choose_behaviour(capacity, limit, online, drain, previous):
    """Use a 75-80% band; never force discharge at or below the target."""
    if not 0 <= capacity <= 100:
        raise ValueError("Invalid battery percentage")
    if limit != 80 or not online:
        return "auto"
    if drain and capacity > 80:
        return "auto-discharge"
    if capacity >= 80:
        return "inhibit-charge"
    if capacity > 75 and previous in ("inhibit-charge", "auto-discharge"):
        return "inhibit-charge"
    return "auto"


def drain_enabled():
    try:
        config = json.loads(CONFIG.read_text())
        return isinstance(config, dict) and config.get("autoDischarge") is True
    except (OSError, ValueError):
        return False


def set_behaviour(mode):
    path = BATTERY / "charge_behaviour"
    text = path.read_text().strip()
    if mode not in text.replace("[", "").replace("]", "").split():
        raise RuntimeError("Charging mode is not supported: " + mode)
    current = selected_behaviour(text)
    if current != mode:
        # These modes use separate SMC inhibitor bits. Setting inhibit-charge
        # alone does not clear force-discharge, so release the previous mode
        # before entering the next one.
        if current != "auto" and mode != "auto":
            path.write_text("auto\n")
            if selected_behaviour(path.read_text()) != "auto":
                raise RuntimeError("Could not release the previous charging mode")
        path.write_text(mode + "\n")
        if selected_behaviour(path.read_text()) != mode:
            raise RuntimeError("Charging mode did not take effect: " + mode)
        print("Charging mode: " + mode, flush=True)


def step():
    # Read all inputs before any write. Any failure restores automatic mode
    # in the daemon's finally clause and causes a service restart.
    capacity = int((BATTERY / "capacity").read_text().strip())
    limit = int((BATTERY / "charge_control_end_threshold").read_text().strip())
    online_text = AC.read_text().strip()
    if online_text not in ("0", "1"):
        raise ValueError("Invalid charger state")
    previous = selected_behaviour((BATTERY / "charge_behaviour").read_text())
    if previous is None:
        raise ValueError("Unknown charging mode")
    mode = choose_behaviour(capacity, limit, online_text == "1",
                            drain_enabled(), previous)
    set_behaviour(mode)
    temporary = STATUS.with_suffix(".tmp")
    temporary.write_text(json.dumps({"mode": mode, "updated": time.monotonic()}) + "\n")
    temporary.replace(STATUS)


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in (
            "daemon", "reset", "drain-on", "drain-off"):
        raise SystemExit("Usage: charge-guard.py daemon|reset|drain-on|drain-off")
    if os.geteuid() != 0:
        raise SystemExit("Administrator authentication is required")
    action = sys.argv[1]
    if action == "reset":
        set_behaviour("auto")
    elif action in ("drain-on", "drain-off"):
        if action == "drain-on":
            options = (BATTERY / "charge_behaviour").read_text()
            if "auto-discharge" not in options:
                raise SystemExit("This Mac does not support plugged-in discharge")
        # Root-owned configuration, published atomically. Do not change sysfs
        # here: the single daemon owns all mode transitions.
        temporary = CONFIG.with_suffix(".tmp")
        with temporary.open("w", encoding="utf-8") as handle:
            json.dump({"autoDischarge": action == "drain-on"}, handle)
            handle.write("\n")
        temporary.chmod(0o644)
        temporary.replace(CONFIG)
    else:
        signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
        signal.signal(signal.SIGINT, lambda *_: sys.exit(0))
        try:
            while True:
                step()
                time.sleep(5)
        finally:
            set_behaviour("auto")


if __name__ == "__main__":
    main()
