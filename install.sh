#!/bin/bash
# Install or update the Apple Silicon Power bar widget for Omarchy.
#
#   curl -fsSL https://raw.githubusercontent.com/RobbieUK1/apple-silicon-power/main/install.sh | bash
#
# Clones the plugin into ~/.config/omarchy/plugins/, reloads the shell's plugin
# list, and puts the widget on the bar (a widget already there is left where it
# is). Running it again updates in place.
set -euo pipefail

repo="https://github.com/RobbieUK1/apple-silicon-power.git"
plugin_id="robbie.apple-silicon-power"
plugins_dir="${OMARCHY_PLUGINS_DIR:-$HOME/.config/omarchy/plugins}"
dest="$plugins_dir/$plugin_id"

command -v git >/dev/null || {
  echo "git is required." >&2
  exit 1
}

if [[ -d $dest/.git ]]; then
  echo "Updating $plugin_id"
  if ! git -C "$dest" pull --ff-only --quiet; then
    echo "Could not fast-forward $dest; keeping the checkout as it is." >&2
  fi
elif [[ -e $dest ]]; then
  echo "$dest exists but is not a git checkout; move it aside and re-run." >&2
  exit 1
else
  echo "Installing $plugin_id"
  mkdir -p "$plugins_dir"
  git clone --depth 1 --quiet "$repo" "$dest"
fi

if [[ ! -e /sys/class/power_supply/macsmc-battery ]]; then
  echo "Warning: no macsmc-battery found. This widget needs Apple Silicon (Asahi)." >&2
fi

if ! command -v omarchy-shell >/dev/null; then
  echo "Installed. Start the Omarchy shell, then run:"
  echo "  omarchy bar put $plugin_id --before omarchy.power"
  exit 0
fi

if ! omarchy-shell shell ping >/dev/null 2>&1; then
  echo "Installed. The shell is not running; after it starts, run:"
  echo "  omarchy bar put $plugin_id --before omarchy.power"
  exit 0
fi

# A new plugin is not a known widget until the shell rescans its plugin folder.
omarchy-shell -q shell rescanPlugins || true
sleep 1

if omarchy bar put "$plugin_id" --before omarchy.power; then
  echo "Done. Click the battery icon on the bar."
else
  echo "Installed, but the widget could not be put on the bar." >&2
  echo "Try: omarchy bar put $plugin_id --before omarchy.power" >&2
  exit 1
fi
