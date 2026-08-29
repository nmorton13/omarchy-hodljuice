#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

jq -e '
  .schemaVersion == 1 and
  .id == "nmorton.hodljuice" and
  (.kinds | index("bar-widget")) != null and
  .entryPoints.barWidget == "BarWidget.qml" and
  .barWidget.allowMultiple == false
' manifest.json >/dev/null

test -f BarWidget.qml
test -f Panel.qml
test -f Model.js
test -f components/SignalVisualizer.qml
test -x bin/hodljuice
