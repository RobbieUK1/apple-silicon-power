function parse(raw) {
  try {
    var data = JSON.parse(String(raw || ""))
    return data && typeof data === "object" && !Array.isArray(data) ? data : ({})
  } catch (error) {
    return ({})
  }
}

function clamp(value, low, high) {
  return Math.max(low, Math.min(high, value))
}

function batteryIcon(data, charging) {
  var percentage = Number(data && data.percentage)
  if (!isFinite(percentage) || percentage < 0) return "󰂑"

  var chargingIcons = ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
  var defaultIcons = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
  var index = clamp(Math.floor(percentage / 10), 0, 9)

  if (data && data.state === "full") return "󰂅"
  if (charging) return chargingIcons[index]
  return defaultIcons[index]
}

// omarchy-powerprofiles-list --active-state prints "profile\t1" for the
// active profile and "profile\t0" for the rest.
function parseProfiles(raw) {
  var profiles = []
  var activeProfile = ""
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (line === "") continue
    var parts = line.split("\t")
    var name = parts[0]
    if (!/^[a-z0-9-]+$/.test(name)) continue
    profiles.push(name)
    if (parts[1] === "1") activeProfile = name
  }
  return { profiles: profiles, activeProfile: activeProfile }
}

function selectProfileIndex(index, delta, count) {
  if (!(count > 0)) return 0
  return clamp((Number(index) || 0) + delta, 0, count - 1)
}

function profileIcon(name) {
  if (name === "power-saver") return "󰌪"
  if (name === "balanced") return "󰊚"
  if (name === "performance") return "󰓅"
  return "󰂄"
}

function profileLabel(name, strings) {
  var value = String(name || "")
  if (value === "power-saver") return strings.t("profilePowerSaver")
  if (value === "balanced") return strings.t("profileBalanced")
  if (value === "performance") return strings.t("profilePerformance")
  return value.charAt(0).toUpperCase() + value.slice(1)
}

if (typeof module !== "undefined") {
  module.exports = {
    parse: parse,
    clamp: clamp,
    batteryIcon: batteryIcon,
    parseProfiles: parseProfiles,
    selectProfileIndex: selectProfileIndex,
    profileIcon: profileIcon,
    profileLabel: profileLabel
  }
}
