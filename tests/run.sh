#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

python3 -m unittest discover -s tests -p 'test_*.py' -v
node tests/model.test.js
python3 -m py_compile bin/hodljuice
node --check tests/model.test.js
jq empty manifest.json
bash tests/validate-manifest.sh
bash -n tests/*.sh

if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin validate .
else
  echo "notice: omarchy not installed; skipping plugin manifest validation"
fi

if command -v qmllint >/dev/null 2>&1; then
  if [ -n "${OMARCHY_PATH:-}" ]; then
    # qmllint resolves dotted modules (qs.Commons) from a qs/ directory
    # layout, which the Omarchy install does not use, so mirror it.
    qml_imports=$(mktemp -d)
    mkdir -p "$qml_imports/qs"
    ln -s "$OMARCHY_PATH/shell/Commons" "$qml_imports/qs/Commons" 2>/dev/null || true
    ln -s "$OMARCHY_PATH/shell/Ui" "$qml_imports/qs/Ui" 2>/dev/null || true
    qmllint -I "$qml_imports" BarWidget.qml Panel.qml components/*.qml
    rm -rf "$qml_imports"
  else
    echo "notice: OMARCHY_PATH is unset; skipping QML lint"
  fi
else
  echo "notice: qmllint not installed; skipping QML lint"
fi

echo "validation: all checks passed"
