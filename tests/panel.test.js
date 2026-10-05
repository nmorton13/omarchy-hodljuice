const fs = require("fs")
const vm = require("vm")
const assert = require("assert")

// Exercise the panel's real state transitions without a desktop or audio player.
const source = fs.readFileSync("Panel.qml", "utf8")
const names = ["toggleTuner", "chooseTuner", "openYears", "chooseYear", "openSearch", "submitSearch", "finishSearch", "focusSearchResults", "playSearchEpisode", "playSavedEpisode", "playSelectedEpisode", "moveFocus"]
const functions = names.map(name => {
  const match = source.match(new RegExp("^  function " + name + "\\([^]*?^  }", "m"))
  assert.ok(match, "Panel function exists: " + name)
  return match[0]
}).join("\n")

function context() {
  const current = {title: "Playing now", audioUrl: "https://example.test/current.mp3"}
  const value = {
    episode: current, playbackState: "playing", errorMessage: "", viewMode: "receiver",
    range: "7", searchRange: "any", searchQuery: "", searchResults: [], searchIndex: 0,
    searchLoading: false, searchComplete: false, searchError: "", cursorActive: false,
    canSelectEpisode: true, saved: true, savedEpisodes: [], resumeSeconds: 30, positionSeconds: 80, durationSeconds: 100,
    autoplayPending: false, recoverWithRetune: true, automaticRetuneAttempts: 1,
    tunerRanges: [{value: "any"}, {value: "7"}, {value: "30"}, {value: "year"}],
    yearOptions: [{value: "2026"}, {value: "2025"}, {value: "2024"}, {value: "2023"}],
    tunerIndex: 0, yearIndex: 0, pendingRange: "any",
    Model: {normalizeRange: value => value},
    cliCommand: args => ["bin/hodljuice", ...args],
    persistPosition: () => {}, checkResume: () => {}, checkSaved: () => {}, ensureSearchVisible: () => {},
    automaticRetuneTimer: {stop: () => {}},
    searchProcess: {running: false, resultValues: null, failureMessage: ""},
    searchInput: {forceActiveFocus: () => {}}, keyCatcher: {forceActiveFocus: () => {}},
    Qt: {callLater: callback => callback()},
  }
  value.root = value
  vm.createContext(value)
  vm.runInContext(functions, value)
  return value
}

let panel = context()
panel.openSearch()
assert.strictEqual(panel.viewMode, "search")
assert.strictEqual(panel.searchRange, "7")
assert.strictEqual(panel.episode.title, "Playing now")
assert.strictEqual(panel.playbackState, "playing")

panel.searchQuery = "  Lyn Alden  "
panel.submitSearch()
assert.deepStrictEqual(Array.from(panel.searchProcess.command), ["bin/hodljuice", "search", "--query", "Lyn Alden", "--range", "7", "--json"])
assert.strictEqual(panel.searchLoading, true)
assert.strictEqual(panel.playbackState, "playing")
assert.strictEqual(panel.episode.title, "Playing now")
const command = panel.searchProcess.command
panel.searchQuery = "another query"
panel.submitSearch()
assert.strictEqual(panel.searchProcess.command, command)

panel = context()
panel.searchQuery = "   "
panel.submitSearch()
assert.strictEqual(panel.searchProcess.running, false)
assert.ok(panel.searchError)

panel = context()
panel.viewMode = "search"
panel.searchLoading = true
panel.searchProcess.resultValues = []
panel.finishSearch(0)
assert.strictEqual(panel.searchLoading, false)
assert.strictEqual(panel.searchComplete, true)
assert.strictEqual(panel.searchResults.length, 0)
assert.strictEqual(panel.searchError, "")
assert.strictEqual(panel.playbackState, "playing")

panel = context()
panel.searchProcess.failureMessage = "Service unavailable"
panel.finishSearch(1)
assert.strictEqual(panel.searchError, "Service unavailable")
assert.strictEqual(panel.errorMessage, "")
assert.strictEqual(panel.episode.title, "Playing now")
assert.strictEqual(panel.playbackState, "playing")

panel = context()
panel.searchProcess.resultValues = null
panel.finishSearch(0)
assert.ok(panel.searchError)

panel = context()
panel.viewMode = "receiver" // User left search while the request was running.
panel.searchProcess.resultValues = [{title: "A result", audioUrl: "https://example.test/result.mp3"}]
panel.finishSearch(0)
assert.strictEqual(panel.viewMode, "receiver")
assert.strictEqual(panel.episode.title, "Playing now")

panel = context()
panel.viewMode = "search"
panel.searchResults = [{title: "A result", audioUrl: "https://example.test/result.mp3"}]
panel.playSearchEpisode(0)
assert.strictEqual(panel.episode.title, "A result")
assert.strictEqual(panel.viewMode, "receiver")
assert.strictEqual(panel.saved, false)
assert.strictEqual(panel.autoplayPending, true)
assert.strictEqual(panel.recoverWithRetune, false) // Explicit selections must not silently retune.
assert.strictEqual(panel.resumeSeconds, 0)

panel = context()
panel.canSelectEpisode = false
panel.searchResults = [{title: "A result", audioUrl: "https://example.test/result.mp3"}]
panel.playSearchEpisode(0)
assert.strictEqual(panel.episode.title, "Playing now")

panel = context()
panel.viewMode = "search"
panel.searchResults = [{}, {}, {}]
panel.moveFocus(0, 1)
assert.strictEqual(panel.searchIndex, 1)
panel.moveFocus(0, -1)
assert.strictEqual(panel.searchIndex, 0)

panel = context()
panel.savedEpisodes = [{title: "Saved result", audioUrl: "https://example.test/saved.mp3"}]
panel.playSavedEpisode(0)
assert.strictEqual(panel.episode.title, "Saved result")
assert.strictEqual(panel.saved, true)
assert.strictEqual(panel.recoverWithRetune, false)

panel = context()
panel.range = "2025"
panel.toggleTuner()
assert.strictEqual(panel.pendingRange, "2025")
assert.strictEqual(panel.viewMode, "tuner")
panel.chooseTuner(3)
assert.strictEqual(panel.viewMode, "years")
assert.strictEqual(panel.yearIndex, 1)
panel.chooseYear(2)
assert.strictEqual(panel.pendingRange, "2024")
assert.strictEqual(panel.viewMode, "tuner")
assert.strictEqual(panel.playbackState, "playing")
panel.range = panel.pendingRange
panel.openSearch()
panel.searchQuery = "bitcoin"
panel.submitSearch()
assert.deepStrictEqual(Array.from(panel.searchProcess.command), ["bin/hodljuice", "search", "--query", "bitcoin", "--range", "2024", "--json"])

panel = context()
panel.viewMode = "years"
panel.moveFocus(0, 1)
assert.strictEqual(panel.yearIndex, 2)
panel.moveFocus(1, 0)
assert.strictEqual(panel.yearIndex, 3)

// Query editing must not dispatch J/K, spaces, or playback shortcuts.
const catcher = source.slice(source.indexOf("  component ReceiverKeyCatcher:"))
const handler = catcher.match(/Keys\.onPressed: function\(event\) {[^]*?^    }/m)
assert.ok(handler)
const emissions = []
const keys = {blocked: true, Qt: {},
  closeRequested: () => emissions.push("close"), tabRequested: () => emissions.push("tab"),
  moveRequested: () => emissions.push("move"), activateRequested: () => emissions.push("activate"),
  textKey: () => emissions.push("text"),
}
vm.createContext(keys)
vm.runInContext("var pressed = (" + handler[0].replace("Keys.onPressed: ", "") + ")", keys)
for (const text of ["j", "k", "s", "r", "t", "b", " ", "/"]) {
  const event = {text, key: 0, accepted: false}
  keys.pressed(event)
  assert.strictEqual(event.accepted, false)
}
assert.strictEqual(emissions.length, 0)

console.log("panel state tests: ok")
