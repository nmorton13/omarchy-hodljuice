.pragma library

var BAND_COUNT = 21
var VALID_RANGES = ["any", "7", "30"]
var DEFAULT_RANGE = "any"

function normalizeRange(value) {
  return VALID_RANGES.indexOf(value) >= 0 ? value : DEFAULT_RANGE
}

function finiteNumber(value) {
  if (value === null || value === undefined || value === "") return null
  var number = Number(value)
  return isFinite(number) ? number : null
}

function clamp(value, minimum, maximum) {
  return Math.max(minimum, Math.min(maximum, value))
}

function safeLabel(value, maximumLength) {
  var limit = finiteNumber(maximumLength)
  if (limit === null || limit < 1) limit = 80
  return String(value || "")
    .replace(/[<>]/g, function(character) { return character === "<" ? "‹" : "›" })
    .replace(/[\u0000-\u001f\u007f]+/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, Math.floor(limit))
}

function normalizeBands(values) {
  var result = []
  var source = Array.isArray(values) ? values : []
  for (var index = 0; index < BAND_COUNT; index++) {
    var value = finiteNumber(source[index])
    result.push(value === null ? 0 : clamp(value, 0, 1))
  }
  return result
}

function parseEpisode(text) {
  try {
    var value = JSON.parse(String(text || ""))
    if (!value || typeof value !== "object" || !value.audioUrl || !value.title) return null
    return value
  } catch (error) {
    return null
  }
}

function parseEpisodeList(text) {
  try {
    var values = JSON.parse(String(text || ""))
    if (!Array.isArray(values)) return null
    return values.filter(function(value) {
      return value && typeof value === "object" && String(value.audioUrl || "") !== "" && String(value.title || "") !== ""
    })
  } catch (error) {
    return null
  }
}

function parsePeople(text) {
  try {
    var values = JSON.parse(String(text || ""))
    if (!Array.isArray(values)) return null
    return values.filter(function(value) {
      return value && typeof value === "object" && String(value.value || "") !== "" && String(value.label || "") !== ""
    }).map(function(value) {
      return { value: String(value.value), label: String(value.label) }
    })
  } catch (error) {
    return null
  }
}

function parseSpectrum(text) {
  try {
    var values = JSON.parse(String(text || ""))
    if (!Array.isArray(values) || values.length !== BAND_COUNT) return null
    return normalizeBands(values)
  } catch (error) {
    return null
  }
}

function parsePlaybackStatus(text) {
  try {
    var value = JSON.parse(String(text || ""))
    if (!value || typeof value !== "object") return null
    var state = String(value.playback || "stopped")
    if (["playing", "paused", "stopped"].indexOf(state) < 0) return null
    return {
      playback: state,
      position: finiteNumber(value.position),
      duration: finiteNumber(value.duration),
      volume: finiteNumber(value.volume)
    }
  } catch (error) {
    return null
  }
}

function progress(position, duration) {
  var current = finiteNumber(position)
  var total = finiteNumber(duration)
  if (current === null || total === null || total <= 0) return 0
  return clamp(current / total, 0, 1)
}

function formatClock(seconds) {
  var value = finiteNumber(seconds)
  if (value === null || value < 0) return "--:--"
  value = Math.floor(value)
  var hours = Math.floor(value / 3600)
  var minutes = Math.floor((value % 3600) / 60)
  var remainder = value % 60
  function pad(number) { return number < 10 ? "0" + number : String(number) }
  return hours > 0 ? hours + ":" + pad(minutes) + ":" + pad(remainder) : minutes + ":" + pad(remainder)
}

// Retained for the not-yet-restored category/people filters; the current tuner
// only exposes time ranges, which filterLabel() covers.
function bandLabel(value) {
  switch (String(value || "all")) {
  case "humanitarian": return "HUMAN RIGHTS"
  case "climate_energy": return "CLIMATE / ENERGY"
  case "video": return "FILM / VIDEO"
  case "money": return "MONEY"
  case "people": return "PEOPLE"
  default: return "ALL BITCOIN"
  }
}

function compactSignal(values, active) {
  if (!active) return "─────"
  var source = normalizeBands(values)
  var indexes = [1, 6, 11, 16, 20]
  var glyphs = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
  return indexes.map(function(index) {
    return glyphs[Math.round(clamp(source[index], 0, 1) * (glyphs.length - 1))]
  }).join("")
}

function filterLabel(value) {
  var text = String(value || "any")
  if (text === "7") return "LAST 7 DAYS"
  if (text === "30") return "LAST 30 DAYS"
  return "ANY TIME"
}

function playbackLabel(state) {
  switch (String(state || "idle")) {
  case "loading": return "TUNING"
  case "buffering": return "BUFFERING"
  case "playing": return "SIGNAL"
  case "paused": return "PAUSED"
  case "error": return "SIGNAL LOST"
  default: return "STANDBY"
  }
}
