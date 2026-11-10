import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "guard", Path(__file__).resolve().parents[1] / "system/charge-guard.py")
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


class PolicyTests(unittest.TestCase):
    def choose(self, capacity, *, limit=80, online=True, drain=True, previous="auto"):
        return guard.choose_behaviour(capacity, limit, online, drain, previous)

    def test_excess_charge_drains(self):
        self.assertEqual(self.choose(97), "auto-discharge")

    def test_target_stops_discharge_and_blocks_charge(self):
        self.assertEqual(self.choose(80, previous="auto-discharge"), "inhibit-charge")

    def test_hysteresis_prevents_repeated_recharging(self):
        self.assertEqual(self.choose(78, previous="inhibit-charge"), "inhibit-charge")
        self.assertEqual(self.choose(75, previous="inhibit-charge"), "auto")
        self.assertEqual(self.choose(74, previous="auto-discharge"), "auto")

    def test_charging_below_target_still_allowed(self):
        self.assertEqual(self.choose(78), "auto")

    def test_disabling_drain_keeps_charge_blocked(self):
        self.assertEqual(self.choose(97, drain=False, previous="auto-discharge"), "inhibit-charge")

    def test_full_charge_override_releases_discharge(self):
        self.assertEqual(self.choose(97, limit=100, previous="auto-discharge"), "auto")

    def test_unplug_releases_discharge(self):
        self.assertEqual(self.choose(97, online=False, previous="auto-discharge"), "auto")

    def test_never_forces_discharge_at_or_below_target(self):
        for percent in range(81):
            for previous in ("auto", "inhibit-charge", "auto-discharge"):
                self.assertNotEqual(self.choose(percent, previous=previous), "auto-discharge")

    def test_invalid_percentage_rejected(self):
        for percent in (-1, 101):
            with self.assertRaises(ValueError):
                self.choose(percent)

    def test_parse_active_mode(self):
        self.assertEqual(guard.selected_behaviour("auto inhibit-charge [auto-discharge]"), "auto-discharge")
        self.assertIsNone(guard.selected_behaviour("auto"))

    def test_bad_config_does_not_enable_discharge(self):
        with tempfile.TemporaryDirectory() as td:
            config = Path(td) / "config"
            with patch.object(guard, "CONFIG", config):
                self.assertFalse(guard.drain_enabled())
                for text in ("invalid", "[]", '{"autoDischarge":"true"}'):
                    config.write_text(text)
                    self.assertFalse(guard.drain_enabled())
                config.write_text('{"autoDischarge":true}')
                self.assertTrue(guard.drain_enabled())

    def test_daemon_restores_auto_when_a_read_fails(self):
        with patch.object(sys, "argv", ["charge-guard.py", "daemon"]), \
                patch.object(guard.os, "geteuid", return_value=0), \
                patch.object(guard, "step", side_effect=OSError("read failed")), \
                patch.object(guard, "set_behaviour") as write:
            with self.assertRaises(OSError):
                guard.main()
            write.assert_called_once_with("auto")

    def test_mode_switch_clears_separate_inhibitor_bits(self):
        class ModeFile:
            mode = "auto-discharge"
            writes = []

            def read_text(self):
                return " ".join("[" + m + "]" if m == self.mode else m
                                for m in ("auto", "inhibit-charge", "auto-discharge"))

            def write_text(self, text):
                self.writes.append(text.strip())
                self.mode = text.strip()

        class BatteryPath:
            def __truediv__(self, _):
                return mode_file

        mode_file = ModeFile()
        with patch.object(guard, "BATTERY", BatteryPath()):
            guard.set_behaviour("inhibit-charge")
        self.assertEqual(mode_file.writes, ["auto", "inhibit-charge"])

    def test_step_uses_display_percentage_and_physical_charger(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            bat = root / "battery"
            bat.mkdir()
            (bat / "capacity").write_text("97")
            (bat / "charge_control_end_threshold").write_text("80")
            (bat / "charge_behaviour").write_text("[auto] inhibit-charge auto-discharge")
            ac = root / "ac"
            ac.write_text("1")
            with patch.object(guard, "BATTERY", bat), patch.object(guard, "AC", ac), \
                    patch.object(guard, "STATUS", root / "status"), \
                    patch.object(guard, "drain_enabled", return_value=True), \
                    patch.object(guard, "set_behaviour") as write:
                guard.step()
                write.assert_called_with("auto-discharge")
                (bat / "capacity").write_text("80")
                guard.step()
                write.assert_called_with("inhibit-charge")
                ac.write_text("0")
                guard.step()
                write.assert_called_with("auto")


if __name__ == "__main__":
    unittest.main()
