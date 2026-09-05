import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "nmorton.hodljuice"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }
  function retune() { if (panelLoader.item) panelLoader.item.retune() }
  function togglePlayback() { if (panelLoader.item) panelLoader.item.togglePlayback() }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  readonly property string playbackState: panelLoader.item ? panelLoader.item.playbackState : "idle"
  readonly property string podcastName: panelLoader.item ? panelLoader.item.podcastName : ""
  readonly property var signalBands: panelLoader.item ? panelLoader.item.signalBands : []
  readonly property string barMode: settings && settings.barMode ? String(settings.barMode) : "signal-title"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: {
      if (root.barMode === "icon") return "HJ"
      var signalActive = root.playbackState === "playing" || root.playbackState === "loading"
      var state = Model.compactSignal(root.signalBands, signalActive)
      if (root.barMode === "signal") return state
      var label = root.podcastName ? Model.safeLabel(root.podcastName) : "HodlJuice"
      return state + "  " + label
    }
    fontSize: Style.font.bodySmall
    horizontalMargin: Style.space(8)
    tooltipText: "HodlJuice — left: receiver, middle: Retune, right: play/pause"

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) root.togglePlayback()
      else if (mouseButton === Qt.MiddleButton) root.retune()
      else root.toggle()
    }
  }
}
