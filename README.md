# Apple Silicon Power

An [Omarchy](https://omarchy.org) bar widget for Apple Silicon laptops. It reads
the `macsmc` battery straight from sysfs, so it can show the readings the stock
power panel leaves out.

Made for Omarchy on Asahi Linux (Arch Linux ARM, `aarch64`).

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/RobbieUK1/apple-silicon-power/main/install.sh | bash
```

That one line clones the plugin into `~/.config/omarchy/plugins/robbie.apple-silicon-power`,
has the shell rescan its plugins, and puts the widget on the bar. Re-run the same
line to update, then restart the shell (`omarchy-restart-shell`) if a change does
not appear.

## What it shows

Click the bar icon for the full panel:

- **Battery life** — time left while discharging, or time to the configured
  charge limit while charging.
- **Battery health compared to new** — full charge capacity as a percentage of
  the design capacity, plus both figures in Wh.
- **Current charge** — percentage in the bar (right-click toggles it) and in
  the panel.
- **Rate of discharge or charge** — instantaneous watts with a direction arrow.
- **Voltage** — the pack voltage while discharging or charging.
- **Temperature** — the pack temperature from the SMC.
- **Charge cycles** — the SMC cycle count.
- **Charge limit** — the Apple Silicon charge threshold, set through Omarchy's
  `omarchy-battery-charge-limit` helper (`80%` longevity or `100%` full). The
  choice is saved for the next boot.
- **Power profile** — the power-profiles-daemon profiles the machine actually
  offers (power-saver, balanced, performance). Picking one saves it through
  `omarchy-powerprofiles-set` for the current AC/battery state.

The widget polls every 30 seconds while closed and every 5 seconds while the
panel is open. Keyboard navigation works on the power-profile row.

## Requirements

- An Apple Silicon Mac running Asahi Linux with the Omarchy shell
  (`quickshell`)
- A `macsmc-battery` power supply (check `ls /sys/class/power_supply/`)
- `omarchy-battery-charge-limit` and `omarchy-powerprofiles-set` (both ship with
  Omarchy)

## Manual install

```bash
git clone https://github.com/RobbieUK1/apple-silicon-power \
  ~/.config/omarchy/plugins/robbie.apple-silicon-power

omarchy-shell shell rescanPlugins
omarchy bar put robbie.apple-silicon-power --before omarchy.power
```

Or place it by hand in `~/.config/omarchy/shell.json` under the right bar
section:

```json
{ "id": "robbie.apple-silicon-power" }
```

It does not replace `omarchy.power`; both can be present. On this hardware the
two do overlap, so most people will want only one.

## Usage

- **Left-click** the bar icon to open the panel.
- **Right-click** to toggle the percentage next to the icon.
- Arrow keys move between power profiles, Enter/space applies the highlighted
  one, Escape closes.

```bash
omarchy bar move robbie.apple-silicon-power --section right
omarchy bar set robbie.apple-silicon-power showPercentage false
```

## Charge-limit authentication

The shell has no terminal, so `set-charge-limit.sh` uses cached `sudo`
credentials when they are still valid and otherwise asks through Omarchy's
polkit agent. Changing the limit is the only action that needs authentication.

Only the values Omarchy's helper supports are offered: `80%` (charging restarts
at 75%) and `100%`. Keeping to those values means the limit is saved with the
same mechanism as `omarchy battery charge limit`, so it survives a reboot.

## Power profiles on Apple Silicon

The profile picker shows whatever power-profiles-daemon reports for the machine,
so it stays honest rather than hard-coding a list. On Asahi hardware with the
current `power-profiles-daemon`, the three profiles only toggle the global
`cpufreq` boost switch:

| Profile | `cpufreq/boost` | Governor |
|---------|-----------------|----------|
| power-saver | `0` | `schedutil` |
| balanced | `1` | `schedutil` |
| performance | `1` | `schedutil` |

So balanced and performance are currently identical here, and power-saver only
removes the (rarely reached) boost states. If the picker ever offers just
regular and low power, that is the daemon reporting what the kernel exposes.

## Files

| File | Purpose |
|------|---------|
| `install.sh` | One-line installer and updater |
| `Panel.qml` | Bar button, keyboard panel, and all layout |
| `battery.py` | Reads `macsmc` telemetry from sysfs and prints JSON |
| `Battery.js` | Parsing, icon, and profile helpers |
| `set-charge-limit.sh` | Privilege-aware wrapper around the Omarchy helper |
| `i18n/en.json` | Display strings |
| `manifest.json` | Plugin manifest |

## License

MIT — see [LICENSE](LICENSE).
