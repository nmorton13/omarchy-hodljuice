import QtQuick
import qs.Commons

Item {
  id: root

  property var bands: []
  property color signalColor: Color.accent
  property color baselineColor: Color.muted
  property bool reduceMotion: false
  property int barCount: 21
  property real minimumLevel: 0.04

  function levelAt(index) {
    if (!Array.isArray(bands) || index >= bands.length) return 0
    var value = Number(bands[index])
    if (!isFinite(value)) return 0
    return Math.max(0, Math.min(1, value))
  }

  Row {
    anchors.fill: parent
    spacing: Math.max(1, Math.round(width / 150))

    Repeater {
      model: root.barCount

      Item {
        required property int index
        width: Math.max(2, (parent.width - parent.spacing * (root.barCount - 1)) / root.barCount)
        height: parent.height

        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          width: parent.width
          height: Math.max(1, parent.height * Math.max(root.minimumLevel, root.levelAt(parent.index)))
          radius: Math.min(width / 2, 2)
          color: root.levelAt(parent.index) > root.minimumLevel ? root.signalColor : root.baselineColor
          opacity: root.levelAt(parent.index) > root.minimumLevel ? 1 : 0.38

          Behavior on height {
            enabled: !root.reduceMotion
            NumberAnimation { duration: 70; easing.type: Easing.OutCubic }
          }
          Behavior on color { ColorAnimation { duration: root.reduceMotion ? 0 : 100 } }
        }
      }
    }
  }
}
