import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "components"

Panel {
  id: root
  moduleName: "nmorton.hodljuice"
  ipcTarget: "nmorton.hodljuice"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color background: Color.popups.background
  readonly property color accent: Color.accent
  readonly property color muted: Color.muted
  readonly property color urgent: Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool reduceMotion: settings && settings.reduceMotion === true

  property var episode: null
  property string episodeTitle: episode ? String(episode.title || "") : ""
  property string podcastName: episode ? String(episode.podcast || episode.artist || "") : ""
  property string playbackState: "idle"
  property string errorMessage: ""
  property string band: settings && settings.band ? String(settings.band) : "all"
  property string range: settings && settings.range ? String(settings.range) : Model.DEFAULT_RANGE
  property string person: settings && settings.person ? String(settings.person) : ""
  property var signalBands: Model.normalizeBands([])
  property real positionSeconds: 0
  property real durationSeconds: 0
  property real playbackVolume: 70
  property real resumeSeconds: 0
  property bool saved: false
  property bool autoplayPending: false
  property bool recoverWithRetune: true
  property int automaticRetuneAttempts: 0
  readonly property int maximumAutomaticRetunes: 3
  property int tuningFrame: 0
  property int statusFailureCount: 0
  property int spectrumFailureCount: 0
  property int focusIndex: 0
  property bool cursorActive: false
  property string viewMode: "receiver"
  property string pendingBand: band
  property string pendingRange: range
  property string pendingPerson: person
  property int tunerIndex: 0
  property int personIndex: 0
  property int savedIndex: 0
  property var savedEpisodes: []
  property bool savedLoading: false
  property var peopleOptions: []
  property bool peopleLoading: false
  readonly property var tunerRanges: [
    { value: "any", label: "ANY TIME" },
    { value: "7", label: "LAST 7 DAYS" },
    { value: "30", label: "LAST 30 DAYS" }
  ]

  readonly property int panelWidth: Style.space(440)
  readonly property real savedRowHeight: Style.space(58)
  readonly property real savedRowSpacing: Style.space(5)

  function localPath(relativePath) {
    var url = Qt.resolvedUrl(relativePath).toString()
    return decodeURIComponent(url.replace(/^file:\/\//, ""))
  }

  function cliCommand(argumentsList) {
    return [root.localPath("bin/hodljuice")].concat(argumentsList)
  }

  function open() {
    root.controller.show()
    if (!episode && playbackState !== "loading") retune()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() { root.persistPosition(); root.controller.hide() }
  function toggle() { if (root.opened) close(); else open() }
  function closeForPopoutSwitch() { close() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function persistTuning(nextBand, nextRange, nextPerson) {
    var entry = { id: root.moduleName }
    if (root.settings) {
      for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    }
    entry.band = nextBand
    entry.range = nextRange
    entry.person = nextPerson
    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function toggleTuner() {
    if (viewMode === "tuner") {
      viewMode = "receiver"
    } else {
      pendingBand = "all"
      pendingRange = Model.normalizeRange(range)
      pendingPerson = ""
      tunerIndex = 0
      viewMode = "tuner"
    }
  }

  function chooseTuner(index) {
    if (index < tunerRanges.length) {
      pendingBand = "all"
      pendingRange = tunerRanges[index].value
      pendingPerson = ""
    } else {
      applyTuning()
    }
  }

  function openPeople() {
    personIndex = 0
    viewMode = "people"
    if (peopleOptions.length === 0 && !peopleLoading) {
      peopleLoading = true
      peopleProcess.command = cliCommand(["people", "--json"])
      peopleProcess.running = true
    }
  }

  function choosePerson(index) {
    if (index < 0 || index >= peopleOptions.length) return
    pendingBand = "people"
    pendingRange = Model.DEFAULT_RANGE
    pendingPerson = String(peopleOptions[index].value)
    viewMode = "tuner"
  }

  function openSaved() {
    savedIndex = 0
    savedLoading = true
    viewMode = "saved"
    if (savedListProcess.running) return
    savedListProcess.command = cliCommand(["saved"])
    savedListProcess.running = true
  }

  function playSavedEpisode(index) {
    if (index < 0 || index >= savedEpisodes.length) return
    if (resumeProcess.running) {
      Qt.callLater(function() { root.playSavedEpisode(index) })
      return
    }
    autoplayPending = false
    persistPosition()
    var value = savedEpisodes[index]
    episode = value
    saved = true
    resumeSeconds = 0
    positionSeconds = 0
    durationSeconds = 0
    errorMessage = ""
    playbackState = "idle"
    recoverWithRetune = false
    autoplayPending = true
    viewMode = "receiver"
    checkResume()
  }

  function removeSavedEpisode(index) {
    if (index < 0 || index >= savedEpisodes.length || savedRemoveProcess.running) return
    savedRemoveProcess.removeIndex = index
    savedRemoveProcess.removeUrl = String(savedEpisodes[index].audioUrl || "")
    savedRemoveProcess.command = cliCommand(["unsave", "--url", savedRemoveProcess.removeUrl])
    savedRemoveProcess.running = true
  }

  function ensureSavedVisible() {
    if (viewMode !== "saved") return
    Qt.callLater(function() {
      var rowTop = savedList.y + savedIndex * (root.savedRowHeight + root.savedRowSpacing)
      var rowBottom = rowTop + root.savedRowHeight
      if (rowTop < contentFlickable.contentY)
        contentFlickable.contentY = Math.max(0, rowTop)
      else if (rowBottom > contentFlickable.contentY + contentFlickable.height)
        contentFlickable.contentY = Math.max(0, Math.min(contentFlickable.contentHeight - contentFlickable.height, rowBottom - contentFlickable.height))
    })
  }

  function applyTuning() {
    if (pendingBand === "people" && !pendingPerson) { openPeople(); return }
    band = pendingBand
    range = pendingRange
    person = pendingPerson
    persistTuning(band, range, person)
    viewMode = "receiver"
    retune()
  }

  function retune(automatic) {
    if (playbackState === "loading") return
    recoverWithRetune = true
    if (automatic !== true) automaticRetuneAttempts = 0
    autoplayPending = false
    if (resumeProcess.running) resumeProcess.running = false
    persistPosition()
    if (["buffering", "playing", "paused"].indexOf(playbackState) >= 0 && !stopProcess.running) {
      stopProcess.command = cliCommand(["stop"])
      stopProcess.running = true
    }
    errorMessage = ""
    playbackState = "loading"
    tuningFrame = 0
    if (reduceMotion) {
      tuningTimer.stop()
      signalBands = Model.normalizeBands([])
    } else {
      tuningTimer.start()
    }
    var argumentsList = ["discover", "--band", band, "--range", range]
    if (band === "people" && person) argumentsList = argumentsList.concat(["--person", person])
    argumentsList.push("--json")
    discoverProcess.command = cliCommand(argumentsList)
    discoverProcess.running = true
  }

  function checkResume() {
    if (!episode || !episode.audioUrl) return
    if (resumeProcess.running) {
      Qt.callLater(root.checkResume)
      return
    }
    resumeProcess.command = cliCommand(["resume", "--url", String(episode.audioUrl)])
    resumeProcess.running = true
  }

  function autoplayDiscoveredEpisode() {
    if (!autoplayPending || !episode) return
    autoplayPending = false
    playCurrent()
  }

  function recoverUnavailableEpisode(message) {
    autoplayPending = false
    if (!recoverWithRetune) {
      playbackState = "error"
      errorMessage = "This saved episode is unavailable. Remove it or Retune."
      return
    }
    if (automaticRetuneTimer.running) return
    if (automaticRetuneAttempts >= maximumAutomaticRetunes) {
      playbackState = "error"
      errorMessage = "No playable podcast was found after several Retunes. Try again."
      return
    }
    automaticRetuneAttempts++
    playbackState = "error"
    errorMessage = message || "That podcast is unavailable. Retuning…"
    automaticRetuneTimer.restart()
  }

  function persistPosition() {
    if (!episode || !episode.audioUrl || positionProcess.running || positionSeconds <= 0) return
    var value = durationSeconds > 0 && durationSeconds - positionSeconds < 10 ? 0 : positionSeconds
    positionProcess.command = cliCommand(["position", "--url", String(episode.audioUrl), "--seconds", String(value)])
    positionProcess.running = true
  }

  function checkSaved() {
    if (!episode || !episode.audioUrl || savedCheckProcess.running) return
    savedCheckProcess.command = cliCommand(["is-saved", "--url", String(episode.audioUrl)])
    savedCheckProcess.running = true
  }

  function saveCurrent() {
    if (!episode || !episode.audioUrl || saveProcess.running) return
    saveProcess.nextSaved = !saved
    if (saveProcess.nextSaved) {
      saveProcess.command = cliCommand([
        "save",
        "--url", String(episode.audioUrl),
        "--title", String(episode.title || ""),
        "--podcast", String(episode.podcast || ""),
        "--artist", String(episode.artist || ""),
        "--published", String(episode.publishedAt || ""),
        "--artwork", String(episode.artworkUrl || "")
      ])
    } else {
      saveProcess.command = cliCommand(["unsave", "--url", String(episode.audioUrl)])
    }
    saveProcess.running = true
  }

  function playCurrent() {
    if (!episode || !episode.audioUrl) return
    if (watchProcess.running) watchProcess.running = false
    playbackState = "buffering"
    playProcess.command = cliCommand([
      "play",
      "--url", String(episode.audioUrl),
      "--title", String(episode.title || "HodlJuice"),
      "--artist", String(episode.podcast || episode.artist || "HodlJuice"),
      "--start", String(resumeSeconds)
    ])
    playProcess.running = true
  }

  function togglePlayback() {
    if (playbackState === "loading" || playbackState === "buffering" || controlProcess.running) return
    if (!episode) { retune(); return }
    if (playbackState === "idle" || playbackState === "error") { playCurrent(); return }
    controlProcess.command = cliCommand(["toggle"])
    controlProcess.running = true
    playbackState = playbackState === "playing" ? "paused" : "playing"
  }

  function seek(seconds) {
    if (!episode || ["playing", "paused"].indexOf(playbackState) < 0 || controlProcess.running) return
    controlProcess.command = cliCommand(["seek", String(seconds)])
    controlProcess.running = true
    positionSeconds = Math.max(0, Math.min(durationSeconds || Number.MAX_VALUE, positionSeconds + seconds))
  }

  function syncWatch() {
    if (["playing", "paused"].indexOf(playbackState) >= 0) {
      if (!watchProcess.running) {
        watchProcess.command = cliCommand(["watch"])
        watchProcess.running = true
      }
    } else {
      watchRetry.stop()
      statusFailureCount = 0
      if (watchProcess.running) watchProcess.running = false
    }
  }

  function syncSpectrum() {
    if (playbackState === "playing") {
      if (!spectrumProcess.running) {
        spectrumProcess.command = cliCommand(["spectrum"])
        spectrumProcess.running = true
      }
    } else {
      analyzerRetry.stop()
      spectrumFailureCount = 0
      if (spectrumProcess.running) spectrumProcess.running = false
      if (playbackState !== "loading") signalBands = Model.normalizeBands([])
    }
  }

  function activateFocus() {
    if (viewMode === "people") { choosePerson(personIndex); return }
    if (viewMode === "saved") { playSavedEpisode(savedIndex); return }
    if (viewMode === "tuner") { chooseTuner(tunerIndex); return }
    if (focusIndex === 0) seek(-30)
    else if (focusIndex === 1) togglePlayback()
    else if (focusIndex === 2) seek(30)
    else if (focusIndex === 3) retune()
    else if (focusIndex === 4) saveCurrent()
    else if (focusIndex === 5) openSaved()
  }

  function moveFocus(dx, dy) {
    cursorActive = true
    if (viewMode === "people") {
      var peopleTotal = Math.max(1, peopleOptions.length)
      if (dy !== 0) personIndex = (personIndex + (dy > 0 ? 1 : peopleTotal - 1)) % peopleTotal
      return
    }
    if (viewMode === "saved") {
      var savedTotal = Math.max(1, savedEpisodes.length)
      if (dy !== 0) savedIndex = (savedIndex + (dy > 0 ? 1 : savedTotal - 1)) % savedTotal
      ensureSavedVisible()
      return
    }
    if (viewMode === "tuner") {
      var total = tunerRanges.length + 1
      if (dy !== 0) tunerIndex = (tunerIndex + (dy > 0 ? 1 : total - 1)) % total
      else if (dx !== 0) tunerIndex = (tunerIndex + (dx > 0 ? 1 : total - 1)) % total
      return
    }
    if (dy !== 0) focusIndex = (focusIndex + (dy > 0 ? 1 : 5)) % 6
    else if (dx !== 0) focusIndex = (focusIndex + (dx > 0 ? 1 : 5)) % 6
  }

  onOpenedChanged: if (opened) Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  onPlaybackStateChanged: {
    Qt.callLater(root.syncSpectrum)
    Qt.callLater(root.syncWatch)
  }
  Component.onCompleted: {
    var supportedRange = Model.normalizeRange(range)
    if (band !== "all" || person !== "" || supportedRange !== range) {
      band = "all"
      range = supportedRange
      person = ""
      persistTuning(band, range, person)
    }
    restoreProcess.command = cliCommand(["current"])
    restoreProcess.running = true
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function retune(): string { root.retune(); return "ok" }
    function playback(): string { root.togglePlayback(); return "ok" }
    function state(): string {
      return JSON.stringify({
        playback: root.playbackState,
        error: root.errorMessage,
        title: root.episodeTitle,
        podcast: root.podcastName
      })
    }
    function save(): string { root.saveCurrent(); return "ok" }
    function saved(): string { root.open(); root.openSaved(); return "ok" }
    function playSaved(index: int): string {
      if (index < 0 || index >= root.savedEpisodes.length) return "missing saved episode"
      root.playSavedEpisode(index)
      return "ok"
    }
    function tune(): string { root.open(); root.toggleTuner(); return "ok" }
    function people(): string { root.open(); root.openPeople(); return "ok" }
    function all(): string {
      root.open()
      root.pendingBand = "all"
      root.pendingRange = Model.DEFAULT_RANGE
      root.pendingPerson = ""
      root.applyTuning()
      return "ok"
    }
    function person(value: string): string {
      if (!value) return "missing person"
      root.open()
      root.pendingBand = "people"
      root.pendingRange = Model.DEFAULT_RANGE
      root.pendingPerson = value
      root.applyTuning()
      return "ok"
    }
  }

  Timer {
    id: automaticRetuneTimer
    interval: 900
    repeat: false
    onTriggered: root.retune(true)
  }

  Timer {
    id: analyzerRetry
    interval: Math.min(30000, 1200 * Math.pow(2, Math.min(root.spectrumFailureCount, 5)))
    repeat: false
    onTriggered: root.syncSpectrum()
  }

  Timer {
    id: watchRetry
    interval: Math.min(30000, 1200 * Math.pow(2, Math.min(root.statusFailureCount, 5)))
    repeat: false
    onTriggered: root.syncWatch()
  }

  Timer {
    interval: 10000
    running: root.playbackState === "playing" || root.playbackState === "paused"
    repeat: true
    onTriggered: root.persistPosition()
  }

  Timer {
    id: tuningTimer
    interval: 55
    repeat: true
    onTriggered: {
      root.tuningFrame++
      var values = []
      for (var index = 0; index < 21; index++) {
        var distance = Math.abs(index - (root.tuningFrame % 25 - 2))
        values.push(Math.max(0, 1 - distance / 4))
      }
      root.signalBands = values
    }
  }

  Process {
    id: restoreProcess
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var value = Model.parseEpisode(text)
        if (!value) return
        root.episode = value
        root.positionSeconds = 0
        root.durationSeconds = 0
        Qt.callLater(root.checkSaved)
        Qt.callLater(root.checkResume)
      }
    }
    onExited: function() {
      if (!watchProcess.running) {
        watchProcess.command = root.cliCommand(["watch"])
        watchProcess.running = true
      }
    }
  }

  Process {
    id: peopleProcess
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var values = Model.parsePeople(text)
        if (values && values.length > 0) root.peopleOptions = values
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim()) root.errorMessage = text.trim()
    }
    onExited: function(exitCode) {
      root.peopleLoading = false
      if (exitCode !== 0 || root.peopleOptions.length === 0) {
        root.errorMessage = root.errorMessage || "Unable to load people from HodlJuice."
        root.viewMode = "tuner"
      }
    }
  }

  Process {
    id: discoverProcess
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var value = Model.parseEpisode(text)
        if (value) {
          root.episode = value
          root.saved = false
          root.resumeSeconds = 0
          root.positionSeconds = 0
          root.durationSeconds = 0
          root.playbackState = "idle"
          root.autoplayPending = true
          Qt.callLater(root.checkSaved)
          Qt.callLater(root.checkResume)
          root.errorMessage = ""
        } else {
          root.recoverUnavailableEpisode("That result had no playable audio. Retuning…")
        }
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim()) root.errorMessage = text.trim()
    }
    onExited: function(exitCode) {
      tuningTimer.stop()
      root.signalBands = Model.normalizeBands([])
      if (exitCode !== 0)
        root.recoverUnavailableEpisode(root.errorMessage || "Unable to reach HodlJuice. Retuning…")
    }
  }

  Process {
    id: resumeProcess
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var value = JSON.parse(String(text || ""))
          root.resumeSeconds = Math.max(0, Number(value.seconds) || 0)
          if (root.resumeSeconds > 0) root.positionSeconds = root.resumeSeconds
        } catch (error) {}
      }
    }
    onExited: root.autoplayDiscoveredEpisode()
  }

  Process {
    id: positionProcess
    command: []
  }

  Process {
    id: savedCheckProcess
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.saved = String(text).trim() === "true"
    }
  }

  Process {
    id: savedListProcess
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var values = Model.parseEpisodeList(text)
        root.savedEpisodes = values || []
        root.savedIndex = Math.min(root.savedIndex, Math.max(0, root.savedEpisodes.length - 1))
      }
    }
    onExited: function(exitCode) {
      root.savedLoading = false
      if (exitCode !== 0) root.errorMessage = "Unable to load saved episodes."
    }
  }

  Process {
    id: savedRemoveProcess
    property int removeIndex: -1
    property string removeUrl: ""
    command: []
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.errorMessage = "Unable to remove the saved episode."
        return
      }
      var values = root.savedEpisodes.slice()
      if (removeIndex >= 0 && removeIndex < values.length) values.splice(removeIndex, 1)
      root.savedEpisodes = values
      root.savedIndex = Math.min(root.savedIndex, Math.max(0, values.length - 1))
      if (root.episode && String(root.episode.audioUrl || "") === removeUrl) root.saved = false
      root.errorMessage = ""
    }
  }

  Process {
    id: saveProcess
    property bool nextSaved: false
    command: []
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim()) root.errorMessage = text.trim()
    }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.saved = nextSaved
        root.errorMessage = ""
      } else if (!root.errorMessage) {
        root.errorMessage = "Unable to update saved episodes."
      }
    }
  }

  Process {
    id: playProcess
    command: []
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim()) root.errorMessage = text.trim()
    }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.playbackState = "playing"
        root.automaticRetuneAttempts = 0
        root.errorMessage = ""
      } else {
        root.recoverUnavailableEpisode(root.errorMessage || "That podcast could not start. Retuning…")
      }
    }
  }

  Process {
    id: spectrumProcess
    command: []
    stdout: SplitParser {
      onRead: function(line) {
        var values = Model.parseSpectrum(line)
        if (values) {
          root.signalBands = values
          root.spectrumFailureCount = 0
        }
      }
    }
    onExited: function() {
      if (root.playbackState === "playing") {
        root.spectrumFailureCount++
        analyzerRetry.restart()
      }
    }
  }

  Process {
    id: watchProcess
    command: []
    stdout: SplitParser {
      onRead: function(line) {
        var status = Model.parsePlaybackStatus(line)
        if (!status) return
        root.statusFailureCount = 0
        if (root.playbackState === "loading") return
        root.playbackState = status.playback === "stopped" ? "idle" : status.playback
        if (status.position !== null) root.positionSeconds = status.position
        if (status.duration !== null) root.durationSeconds = status.duration
        if (status.volume !== null) root.playbackVolume = status.volume
      }
    }
    onExited: function() {
      if (["playing", "paused"].indexOf(root.playbackState) >= 0) {
        root.statusFailureCount++
        if (root.statusFailureCount >= 3) {
          root.playbackState = "error"
          root.errorMessage = "Playback stopped responding. Press Play to reconnect."
        } else {
          watchRetry.restart()
        }
      }
    }
  }

  Process {
    id: stopProcess
    command: []
  }

  Process {
    id: controlProcess
    command: []
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.playbackState = "error"
        root.errorMessage = "The playback command failed."
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(root.panelWidth)
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(700))

    ReceiverKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveFocus(dx, dy) }
      onActivateRequested: root.activateFocus()
      onCloseRequested: {
        if (root.viewMode === "people") root.viewMode = "tuner"
        else if (root.viewMode === "saved" || root.viewMode === "tuner") root.viewMode = "receiver"
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (root.viewMode === "saved") {
          if (text === "s" || text === "S" || text === "x" || text === "X") root.removeSavedEpisode(root.savedIndex)
          else if (text === "b" || text === "B") root.viewMode = "receiver"
          return
        }
        if (text === "b" || text === "B") { root.openSaved(); return }
        if (text === "t" || text === "T") {
          if (root.viewMode === "people") root.viewMode = "tuner"
          else root.toggleTuner()
          return
        }
        if (root.viewMode !== "receiver") return
        if (text === " " || text === "p" || text === "P") root.togglePlayback()
        else if (text === "r" || text === "R") root.retune()
        else if (text === "h" || text === "H") root.seek(-30)
        else if (text === "l" || text === "L") root.seek(30)
        else if (text === "s" || text === "S") root.saveCurrent()
      }

      Flickable {
        id: contentFlickable
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: content
          width: parent.width
          spacing: Style.space(12)

          Row {
            width: parent.width
            spacing: Style.space(8)
            Text {
              width: parent.width - stateLabel.width - parent.spacing
              text: "HODLJUICE  //  RECEIVER 21"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
            }
            Text {
              id: stateLabel
              text: Model.playbackLabel(root.playbackState)
              color: root.playbackState === "error" ? root.urgent : root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1
            }
          }

          BorderSurface {
            visible: root.viewMode === "receiver"
            width: parent.width
            height: Style.space(132)
            color: root.background
            borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, 1)
            padding: Style.space(14)

            SignalVisualizer {
              anchors.fill: parent
              anchors.topMargin: parent.contentTopInset
              anchors.rightMargin: parent.contentRightInset
              anchors.bottomMargin: parent.contentBottomInset
              anchors.leftMargin: parent.contentLeftInset
              bands: root.signalBands
              signalColor: root.accent
              baselineColor: root.muted
              reduceMotion: root.reduceMotion
            }
          }

          Column {
            visible: root.viewMode === "receiver"
            width: parent.width
            spacing: Style.space(4)
            Text {
              width: parent.width
              text: root.episode ? String(root.episode.podcast || root.episode.artist || "UNKNOWN SOURCE") : (root.playbackState === "loading" ? "SCANNING THE BAND…" : "NO SIGNAL LOCKED")
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1
              elide: Text.ElideRight
            }
            Text {
              width: parent.width
              text: root.episode ? root.episodeTitle : "Press Retune to receive a random Bitcoin podcast."
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
              wrapMode: Text.WordWrap
              maximumLineCount: 3
              elide: Text.ElideRight
            }
            Text {
              width: parent.width
              text: root.episode ? String(root.episode.publishedAt || "") : ""
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Column {
            visible: root.viewMode === "receiver"
            width: parent.width
            spacing: Style.space(5)

            Rectangle {
              width: parent.width
              height: Style.space(4)
              radius: height / 2
              color: Qt.rgba(root.muted.r, root.muted.g, root.muted.b, 0.30)
              Rectangle {
                width: parent.width * Model.progress(root.positionSeconds, root.durationSeconds)
                height: parent.height
                radius: height / 2
                color: root.accent
                Behavior on width {
                  enabled: !root.reduceMotion
                  NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }
              }
            }

            Row {
              width: parent.width
              Text {
                width: parent.width / 2
                text: Model.formatClock(root.positionSeconds)
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                width: parent.width / 2
                text: root.durationSeconds > 0 ? "−" + Model.formatClock(Math.max(0, root.durationSeconds - root.positionSeconds)) : "--:--"
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                horizontalAlignment: Text.AlignRight
              }
            }
          }

          Row {
            visible: root.viewMode === "receiver"
            width: parent.width
            spacing: Style.space(8)

            ReceiverButton {
              width: (parent.width - parent.spacing * 2) / 3
              label: "−30"
              selected: root.cursorActive && root.focusIndex === 0
              enabled: root.episode !== null
              onTriggered: root.seek(-30)
            }
            ReceiverButton {
              width: (parent.width - parent.spacing * 2) / 3
              label: root.playbackState === "playing" ? "PAUSE" : "PLAY"
              selected: root.cursorActive && root.focusIndex === 1
              enabled: root.episode !== null && root.playbackState !== "loading"
              emphasized: true
              onTriggered: root.togglePlayback()
            }
            ReceiverButton {
              width: (parent.width - parent.spacing * 2) / 3
              label: "+30"
              selected: root.cursorActive && root.focusIndex === 2
              enabled: root.episode !== null
              onTriggered: root.seek(30)
            }
          }

          Row {
            visible: root.viewMode === "receiver"
            width: parent.width
            spacing: Style.space(8)

            ReceiverButton {
              width: (parent.width - parent.spacing) * 0.68
              label: root.playbackState === "loading" ? "TUNING…" : "RETUNE"
              selected: root.cursorActive && root.focusIndex === 3
              enabled: root.playbackState !== "loading"
              emphasized: true
              onTriggered: root.retune()
            }
            ReceiverButton {
              width: (parent.width - parent.spacing) * 0.32
              label: root.saved ? "SAVED  ●" : "SAVE  ○"
              selected: root.cursorActive && root.focusIndex === 4
              enabled: root.episode !== null
              onTriggered: root.saveCurrent()
            }
          }

          ReceiverButton {
            visible: root.viewMode === "receiver"
            width: parent.width
            label: "SAVED EPISODES"
            selected: root.cursorActive && root.focusIndex === 5
            onTriggered: root.openSaved()
          }

          Rectangle {
            visible: root.viewMode === "receiver"
            width: parent.width
            height: Style.space(32)
            radius: Style.cornerRadius
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.10)
            border.width: 1
            border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.35)

            Text {
              anchors.centerIn: parent
              text: "ACTIVE FILTER  //  " + Model.filterLabel(root.range)
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 0.8
            }
          }

          Column {
            visible: root.viewMode === "tuner"
            width: parent.width
            spacing: Style.space(12)

            Text {
              width: parent.width
              text: "TUNE THE RECEIVER"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
              font.letterSpacing: 1
            }

            Column {
              width: parent.width
              spacing: Style.space(6)

              Text {
                text: "RANGE"
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1
              }
              Repeater {
                model: root.tunerRanges
                TunerOption {
                  required property var modelData
                  required property int index
                  width: parent.width
                  label: modelData.label
                  choiceIndex: index
                  activeChoice: root.pendingRange === modelData.value
                  selected: root.cursorActive && root.tunerIndex === index
                  onTriggered: root.chooseTuner(index)
                }
              }
            }

            Text {
              width: parent.width
              text: "Choose how far back HodlJuice should search."
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            ReceiverButton {
              width: parent.width
              label: "LOCK SIGNAL  //  " + Model.filterLabel(root.pendingRange)
              selected: root.cursorActive && root.tunerIndex === root.tunerRanges.length
              emphasized: true
              onTriggered: root.applyTuning()
            }
          }

          Column {
            visible: root.viewMode === "saved"
            width: parent.width
            spacing: Style.space(10)

            Text {
              width: parent.width
              text: "SAVED EPISODES"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
              font.letterSpacing: 1
            }
            Text {
              width: parent.width
              text: root.savedLoading ? "LOADING SAVED SIGNALS…" : (root.savedEpisodes.length === 0 ? "No saved episodes yet. Press S while receiving an episode to add one." : "Select an episode to resume and play it.")
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
            Column {
              id: savedList
              visible: !root.savedLoading && root.savedEpisodes.length > 0
              width: parent.width
              spacing: root.savedRowSpacing

              Repeater {
                model: root.savedEpisodes
                SavedEpisodeOption {
                  required property var modelData
                  required property int index
                  width: parent.width
                  podcast: String(modelData.podcast || modelData.artist || "Unknown podcast")
                  episodeTitle: String(modelData.title || "Untitled episode")
                  published: String(modelData.publishedAt || "")
                  choiceIndex: index
                  selected: root.cursorActive && root.savedIndex === index
                  onTriggered: root.playSavedEpisode(index)
                  onRemoveRequested: root.removeSavedEpisode(index)
                }
              }
            }
            Text {
              visible: root.errorMessage !== ""
              width: parent.width
              text: root.errorMessage
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
            ReceiverButton {
              width: parent.width
              label: "BACK TO RECEIVER"
              onTriggered: root.viewMode = "receiver"
            }
          }

          Column {
            visible: root.viewMode === "people"
            width: parent.width
            spacing: Style.space(8)

            Text {
              width: parent.width
              text: "TUNE A PERSON"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
              font.letterSpacing: 1
            }
            Text {
              visible: root.peopleLoading
              width: parent.width
              text: "SCANNING PEOPLE…"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Row {
              visible: !root.peopleLoading
              width: parent.width
              spacing: Style.space(8)

              Column {
                width: (parent.width - parent.spacing) / 2
                spacing: Style.space(5)
                Repeater {
                  model: root.peopleOptions.slice(0, Math.ceil(root.peopleOptions.length / 2))
                  TunerOption {
                    required property var modelData
                    required property int index
                    width: parent.width
                    label: modelData.label
                    choiceIndex: index
                    peopleChoice: true
                    activeChoice: root.pendingPerson === modelData.value
                    selected: root.cursorActive && root.personIndex === index
                    onTriggered: root.choosePerson(index)
                  }
                }
              }

              Column {
                readonly property int offset: Math.ceil(root.peopleOptions.length / 2)
                width: (parent.width - parent.spacing) / 2
                spacing: Style.space(5)
                Repeater {
                  model: root.peopleOptions.slice(parent.offset)
                  TunerOption {
                    required property var modelData
                    required property int index
                    readonly property int globalIndex: parent.offset + index
                    width: parent.width
                    label: modelData.label
                    choiceIndex: globalIndex
                    peopleChoice: true
                    activeChoice: root.pendingPerson === modelData.value
                    selected: root.cursorActive && root.personIndex === globalIndex
                    onTriggered: root.choosePerson(globalIndex)
                  }
                }
              }
            }
          }

          Text {
            visible: root.viewMode === "receiver" && root.errorMessage !== ""
            width: parent.width
            text: "SIGNAL LOST  //  " + root.errorMessage
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          Text {
            width: parent.width
            text: root.viewMode === "receiver" ? "SPACE  ·  H/L  ·  S SAVE  ·  B SAVED  ·  R RETUNE  ·  T TUNE" : (root.viewMode === "saved" ? "↑/↓ SELECT  ·  ENTER PLAY  ·  S REMOVE  ·  ESC BACK" : "↑/↓ SELECT  ·  ENTER CHOOSE  ·  T BACK  ·  ESC BACK")
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            font.letterSpacing: 0.4
          }
        }
      }
    }
  }

  component SavedEpisodeOption: Rectangle {
    id: savedOption
    property string podcast: ""
    property string episodeTitle: ""
    property string published: ""
    property int choiceIndex: 0
    property bool selected: false
    signal triggered()
    signal removeRequested()

    height: root.savedRowHeight
    radius: Style.cornerRadius
    color: selected || savedMouse.containsMouse
      ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
      : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.045)
    border.width: selected ? 1 : 0
    border.color: root.accent

    Column {
      anchors.left: parent.left
      anchors.right: removeButton.left
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)
      Text {
        width: parent.width
        text: savedOption.podcast.toUpperCase() + (savedOption.published ? "  //  " + savedOption.published : "")
        color: root.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        text: savedOption.episodeTitle
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }
    }

    MouseArea {
      id: savedMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: {
        root.cursorActive = true
        root.savedIndex = savedOption.choiceIndex
      }
      onClicked: savedOption.triggered()
    }

    Rectangle {
      id: removeButton
      z: 2
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(62)
      height: Style.space(28)
      radius: Style.cornerRadius
      color: removeMouse.containsMouse
        ? Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.18)
        : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
      Text {
        anchors.centerIn: parent
        text: "REMOVE"
        color: removeMouse.containsMouse ? root.urgent : root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
      MouseArea {
        id: removeMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: savedOption.removeRequested()
      }
    }
  }

  component ReceiverKeyCatcher: Item {
    signal moveRequested(int dx, int dy)
    signal activateRequested()
    signal closeRequested()
    signal tabRequested(int direction)
    signal textKey(string text)

    focus: true
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Escape) {
        closeRequested(); event.accepted = true; return
      }
      if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
        tabRequested((event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab ? -1 : 1)
        event.accepted = true; return
      }
      if (event.key === Qt.Key_Down || event.text === "j" || event.text === "J") {
        moveRequested(0, 1); event.accepted = true; return
      }
      if (event.key === Qt.Key_Up || event.text === "k" || event.text === "K") {
        moveRequested(0, -1); event.accepted = true; return
      }
      if (event.key === Qt.Key_Right) {
        moveRequested(1, 0); event.accepted = true; return
      }
      if (event.key === Qt.Key_Left) {
        moveRequested(-1, 0); event.accepted = true; return
      }
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        activateRequested(); event.accepted = true; return
      }
      if (event.key === Qt.Key_Space) {
        textKey(" "); event.accepted = true; return
      }
      if (event.text && event.text.length === 1) {
        textKey(event.text); event.accepted = true
      }
    }
  }

  component TunerOption: Rectangle {
    id: tunerOption
    property string label: ""
    property int choiceIndex: 0
    property bool peopleChoice: false
    property bool activeChoice: false
    property bool selected: false
    signal triggered()

    height: Style.space(31)
    radius: Style.cornerRadius
    color: {
      if (selected || tunerMouse.containsMouse)
        return Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
      if (activeChoice)
        return Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.10)
      return Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
    }
    border.width: selected || activeChoice ? 1 : 0
    border.color: root.accent

    Row {
      anchors.fill: parent
      anchors.leftMargin: Style.space(9)
      anchors.rightMargin: Style.space(9)
      spacing: Style.space(7)
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: tunerOption.activeChoice ? "●" : "○"
        color: tunerOption.activeChoice ? root.accent : root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - Style.space(25)
        text: tunerOption.label
        color: tunerOption.activeChoice ? root.accent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: tunerOption.activeChoice
        elide: Text.ElideRight
      }
    }

    MouseArea {
      id: tunerMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: {
        root.cursorActive = true
        if (tunerOption.peopleChoice) root.personIndex = tunerOption.choiceIndex
        else root.tunerIndex = tunerOption.choiceIndex
      }
      onClicked: tunerOption.triggered()
    }
  }

  component ReceiverButton: Rectangle {
    id: receiverButton
    property string label: ""
    property bool selected: false
    property bool emphasized: false
    signal triggered()

    height: Style.space(36)
    radius: Style.cornerRadius
    opacity: enabled ? 1 : 0.45
    color: {
      if (selected || buttonMouse.containsMouse)
        return Qt.rgba(root.accent.r, root.accent.g, root.accent.b, emphasized ? 0.24 : 0.14)
      return Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, emphasized ? 0.10 : 0.055)
    }
    border.width: selected ? 1 : 0
    border.color: root.accent

    Text {
      anchors.centerIn: parent
      text: receiverButton.label
      color: receiverButton.emphasized ? root.accent : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      font.letterSpacing: 0.8
    }

    MouseArea {
      id: buttonMouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: receiverButton.enabled
      cursorShape: receiverButton.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: receiverButton.triggered()
    }
  }
}
