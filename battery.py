#!/usr/bin/env python3
# Read Apple Silicon (macsmc) battery telemetry straight from sysfs and print
# one JSON object. Kept free of third-party modules so the shell can run it
# with the system python.
import glob
import json
import os
import math
import time

POWER_SUPPLY = os.environ.get("OMARCHY_POWER_SUPPLY_PATH", "/sys/class/power_supply")
GUARD_HELPER = "/usr/local/lib/apple-silicon-power/charge-guard.py"
GUARD_CONFIG = "/etc/apple-silicon-power.json"
GUARD_STATUS = "/run/apple-silicon-power/status.json"


def guard_info():
    try:
        config = json.loads(read_text(GUARD_CONFIG) or "{}")
    except ValueError:
        config = {}
    try:
        state = json.loads(read_text(GUARD_STATUS) or "{}")
        age = time.monotonic() - float(state.get("updated", -100))
        active = 0 <= age < 20
    except (ValueError, TypeError, AttributeError):
        active = False
    return {
        "guardInstalled": os.path.isfile(GUARD_HELPER),
        "guardActive": active,
        "autoDischarge": isinstance(config, dict) and config.get("autoDischarge") is True,
    }


def read_text(path):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            return handle.read().strip()
    except OSError:
        return None


def read_number(path):
    text = read_text(path)
    if text is None:
        return None
    try:
        value = float(text)
        return value if math.isfinite(value) else None
    except ValueError:
        return None


def read_int(path):
    value = read_number(path)
    return int(round(value)) if value is not None else None


def supplies():
    return sorted(glob.glob(os.path.join(POWER_SUPPLY, "*")))


def find_battery():
    for directory in supplies():
        if read_text(os.path.join(directory, "type")) != "Battery":
            continue
        if read_text(os.path.join(directory, "present")) in ("0", "no"):
            continue
        return directory
    return None


def ac_online():
    mains = []
    usb = []
    for directory in supplies():
        kind = read_text(os.path.join(directory, "type"))
        online = read_text(os.path.join(directory, "online"))
        if online is None:
            continue
        if kind == "Mains":
            mains.append(online == "1")
        elif kind == "USB":
            usb.append(online == "1")
    # Apple Silicon exposes macsmc-ac as the reliable Mains supply. Fall back
    # to USB-C source supplies on machines that only report those.
    values = mains if mains else usb
    return any(values)


def energy_wh(directory, name, voltage):
    value = read_number(os.path.join(directory, name))
    if value is not None:
        return value / 1_000_000.0
    # Driver may report charge in microamp-hours instead of energy. Charge
    # (uAh) x voltage (uV) x 1e-12 is watt-hours.
    charge = read_number(os.path.join(directory, name.replace("energy", "charge")))
    if charge is not None and voltage is not None:
        return charge * (voltage * 1_000_000.0) * 1e-12
    return None


def read_battery(directory):
    status = (read_text(os.path.join(directory, "status")) or "").lower()
    voltage_v = read_number(os.path.join(directory, "voltage_now"))
    voltage_v = voltage_v / 1_000_000.0 if voltage_v is not None else None

    energy_now = energy_wh(directory, "energy_now", voltage_v)
    energy_full = energy_wh(directory, "energy_full", voltage_v)
    energy_design = energy_wh(directory, "energy_full_design", voltage_v)
    percentage = read_int(os.path.join(directory, "capacity"))

    power_w = read_number(os.path.join(directory, "power_now"))
    if power_w is not None:
        power_w = abs(power_w) / 1_000_000.0
    else:
        current_ua = read_number(os.path.join(directory, "current_now"))
        voltage_uv = read_number(os.path.join(directory, "voltage_now"))
        if current_ua is not None and voltage_uv is not None:
            power_w = abs(current_ua * voltage_uv) * 1e-12

    current_a = read_number(os.path.join(directory, "current_now"))
    current_a = current_a / 1_000_000.0 if current_a is not None else None

    temperature = read_number(os.path.join(directory, "temp"))
    temperature = temperature / 10.0 if temperature is not None else None

    threshold_start = read_int(os.path.join(directory, "charge_control_start_threshold"))
    threshold_end = read_int(os.path.join(directory, "charge_control_end_threshold"))
    threshold_supported = threshold_end is not None
    behaviours = read_text(os.path.join(directory, "charge_behaviour")) or ""
    behaviour = next((word[1:-1] for word in behaviours.split()
                      if word.startswith("[") and word.endswith("]")), "")

    health_percent = None
    if energy_full is not None and energy_design and energy_design > 0:
        health_percent = energy_full / energy_design * 100.0

    cycles = read_int(os.path.join(directory, "cycle_count"))

    on_ac = ac_online()
    threshold = threshold_end if threshold_end else 100
    restart = threshold_start if threshold_start is not None else threshold
    holding = bool(
        on_ac
        and threshold < 100
        and percentage is not None
        and (percentage >= threshold or percentage > restart)
        and status in ("not charging", "full")
    )

    # Time left uses the same instantaneous rate shown beside it, so the two
    # numbers always agree. Charging counts up to the charge limit, not to the
    # design capacity.
    time_minutes = None
    time_direction = "none"
    if power_w is not None and power_w > 0.2 and energy_now is not None:
        if status == "discharging":
            time_minutes = energy_now / power_w * 60.0
            time_direction = "left"
        elif on_ac and status in ("charging", "pending-charge") and not holding and energy_full:
            target = energy_full * threshold / 100.0
            remaining = max(0.0, target - energy_now)
            if remaining > 0.01:
                time_minutes = remaining / power_w * 60.0
                time_direction = "toFull"

    return {
        "present": True,
        "path": os.path.basename(directory),
        "state": status,
        "percentage": percentage,
        "acOnline": on_ac,
        "holding": holding,
        "chargeBehaviour": behaviour,
        "dischargeSupported": "auto-discharge" in behaviours.split() or "[auto-discharge]" in behaviours.split(),
        **guard_info(),
        "energyNowWh": energy_now,
        "energyFullWh": energy_full,
        "energyFullDesignWh": energy_design,
        "healthPercent": health_percent,
        "powerW": power_w,
        "currentA": current_a,
        "voltageV": voltage_v,
        "cycles": cycles,
        "temperatureC": temperature,
        "thresholdStart": threshold_start,
        "thresholdEnd": threshold_end,
        "thresholdSupported": threshold_supported,
        "timeMinutes": round(time_minutes) if time_minutes is not None else None,
        "timeDirection": time_direction,
        "manufactureYear": read_int(os.path.join(directory, "manufacture_year")),
        "manufactureMonth": read_int(os.path.join(directory, "manufacture_month")),
        "manufactureDay": read_int(os.path.join(directory, "manufacture_day")),
    }


def main():
    directory = find_battery()
    if directory is None:
        print(json.dumps({"present": False}, separators=(",", ":")))
        return
    print(json.dumps(read_battery(directory), separators=(",", ":")))


if __name__ == "__main__":
    main()
