import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("battery", ROOT / "battery.py")
battery = importlib.util.module_from_spec(spec)
spec.loader.exec_module(battery)


class BatteryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        old_path = battery.POWER_SUPPLY
        self.addCleanup(setattr, battery, "POWER_SUPPLY", old_path)
        battery.POWER_SUPPLY = str(self.root)
        self.bat = self.root / "macsmc-battery"
        self.bat.mkdir()
        self.ac = self.root / "macsmc-ac"
        self.ac.mkdir()
        self.write(self.ac, type="Mains", online="1")
        self.write(self.bat, type="Battery", present="1", status="Not charging",
                   capacity="78", energy_now="39000000", energy_full="50000000",
                   energy_full_design="60000000", voltage_now="12000000",
                   power_now="0", charge_control_start_threshold="75",
                   charge_control_end_threshold="80")

    def write(self, directory, **values):
        for key, value in values.items():
            (directory / key).write_text(value)

    def read(self):
        return battery.read_battery(str(self.bat))

    def test_hold_between_restart_and_limit(self):
        self.assertTrue(self.read()["holding"])
        self.write(self.bat, capacity="75")
        self.assertFalse(self.read()["holding"])

    def test_hold_above_limit(self):
        self.write(self.bat, capacity="96")
        self.assertTrue(self.read()["holding"])

    def test_active_charge_is_not_reported_as_hold(self):
        self.write(self.bat, status="Charging", capacity="80")
        self.assertFalse(self.read()["holding"])

    def test_full_limit_and_unplugged_do_not_hold(self):
        self.write(self.bat, charge_control_end_threshold="100")
        self.assertFalse(self.read()["holding"])
        self.write(self.bat, charge_control_end_threshold="80")
        self.write(self.ac, online="0")
        self.assertFalse(self.read()["holding"])

    def test_discharge_with_charger_connected(self):
        self.write(self.bat, status="Discharging", power_now="10000000")
        data = self.read()
        self.assertTrue(data["acOnline"])
        self.assertFalse(data["holding"])
        self.assertEqual(data["timeMinutes"], 234)
        self.assertEqual(data["timeDirection"], "left")

    def test_charge_estimate_targets_limit(self):
        self.write(self.bat, status="Charging", capacity="70",
                   energy_now="35000000", power_now="10000000")
        self.assertEqual(self.read()["timeMinutes"], 30)

    def test_mains_preferred_over_stale_usb(self):
        usb = self.root / "usb"
        usb.mkdir()
        self.write(usb, type="USB", online="1")
        self.write(self.ac, online="0")
        self.assertFalse(self.read()["acOnline"])

    def test_invalid_numbers_are_unknown(self):
        for value in ("NaN", "inf", "invalid"):
            self.write(self.bat, capacity=value)
            self.assertIsNone(self.read()["percentage"])

    def test_no_battery_cli(self):
        self.write(self.bat, present="0")
        result = subprocess.run(["python3", str(ROOT / "battery.py")],
                                env={**os.environ, "OMARCHY_POWER_SUPPLY_PATH": str(self.root)},
                                capture_output=True, text=True, check=True)
        self.assertEqual(json.loads(result.stdout), {"present": False})


class InstallerTests(unittest.TestCase):
    def test_failed_update_exits_before_shell_changes(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            dest = root / "plugins" / "robbie.apple-silicon-power"
            (dest / ".git").mkdir(parents=True)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            git = bin_dir / "git"
            git.write_text("#!/bin/sh\nexit 1\n")
            git.chmod(0o755)
            result = subprocess.run(["bash", str(ROOT / "install.sh")],
                                    env={**os.environ, "PATH": str(bin_dir) + ":" + os.environ["PATH"],
                                         "OMARCHY_PLUGINS_DIR": str(root / "plugins")},
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertIn("Update failed", result.stderr)
            self.assertNotIn("Done.", result.stdout)


if __name__ == "__main__":
    unittest.main()
