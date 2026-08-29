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
fi

if command -v qmllint >/dev/null 2>&1; then
  qmllint -I "$OMARCHY_PATH/shell" BarWidget.qml Panel.qml components/*.qml
fi

echo "validation: all checks passed"
