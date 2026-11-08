const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")
const Battery = require("../Battery.js")

const unknown = Battery.batteryIcon({}, false)
for (const percentage of [null, undefined, -1, NaN]) {
  assert.equal(Battery.batteryIcon({ percentage }, false), unknown)
}
assert.notEqual(Battery.batteryIcon({ percentage: 0 }, false), unknown)

// Exercise the actual QML data handlers without starting the desktop shell.
const source = fs.readFileSync(require.resolve("../Panel.qml"), "utf8")
function qmlFunction(name) {
  const start = source.indexOf("  function " + name + "(")
  assert.ok(start >= 0)
  const open = source.indexOf("{", start)
  let depth = 1, end = open + 1
  for (; depth > 0; end++) {
    if (source[end] === "{") depth++
    if (source[end] === "}") depth--
  }
  return source.slice(start, end)
}
const context = vm.createContext({
  Battery, strings: { t: key => key }, info: { present: true, percentage: 78 },
  batteryReadFailed: false, profiles: ["balanced"], activeProfile: "balanced",
  profileIndex: 2, cursorActive: false, profileReadError: ""
})
vm.runInContext(qmlFunction("acceptInfo") + "\n" + qmlFunction("acceptProfiles"), context)
for (const raw of ["", "invalid", "[]", '{"present":"true"}']) {
  context.acceptInfo(raw)
  assert.equal(context.batteryReadFailed, true)
  assert.equal(context.info.percentage, undefined)
}
context.acceptInfo('{"present":false}')
assert.equal(context.batteryReadFailed, false)
assert.equal(context.info.present, false)
context.acceptInfo('{"present":true,"percentage":78}')
assert.equal(context.info.percentage, 78)
assert.equal(context.batteryReadFailed, false)

context.acceptProfiles("")
assert.equal(context.profiles.length, 0)
assert.equal(context.activeProfile, "")
assert.equal(context.profileReadError, "profilesUnavailable")
context.acceptProfiles("power-saver\t0\nbalanced\t1\n")
assert.equal(context.activeProfile, "balanced")
assert.equal(context.profileIndex, 1)
assert.equal(context.profileReadError, "")
context.cursorActive = true
context.profileIndex = 2
context.acceptProfiles("balanced\t1\n")
assert.equal(context.profileIndex, 0)
console.log("Helper and panel data-handler regression checks passed.")
