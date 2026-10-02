#!/usr/bin/env bash
# qmllint + qmlformat for the store (`just store-lint`; `--fix` formats in place).
# Quickshell serves the config dir as the `qs` module: a temp import path with qs -> store/
# gives qmllint the same view without a running Quickshell. ui/qmldir must be current
# (tools/gen-qmldir.sh). Known Quickshell-type false positives are filtered below, each
# with its reason.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
qtbin=${QT_BIN:-/usr/lib/qt6/bin}
qml=${QML_IMPORT_PATH:-/usr/lib/qt6/qml}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
ln -s "$here" "$tmp/qs"
status=0

"$here/tools/gen-qmldir.sh" "$tmp/qmldir"
if ! diff -q "$tmp/qmldir" "$here/ui/qmldir" > /dev/null; then
  echo "store/ui/qmldir is stale: run store/tools/gen-qmldir.sh" >&2
  status=1
fi

# Filtered false positives:
#   [signal-handler-parameters] "Type QProcess::ExitStatus ... onExited"  # why: Quickshell's
#     Process.exited(int, QProcess::ExitStatus) names a QtCore enum its qmltypes do not
#     export; the handler compiles and runs (Quickshell 0.3.1, Qt 6.11).
"$qtbin/qmllint" -I "$tmp" -I "$qml" "$here"/shell.qml "$here"/ui/*.qml > "$tmp/lint.txt" 2>&1 || true
grep -E "^(Warning|Error)" "$tmp/lint.txt" | grep -v "Type QProcess::ExitStatus of parameter exitStatus in signal called exited" > "$tmp/issues.txt" || true
if [[ -s $tmp/issues.txt ]]; then
  cat "$tmp/lint.txt" >&2
  echo "qmllint: $(wc -l < "$tmp/issues.txt") issue(s)" >&2
  status=1
fi

if [[ ${1:-} == "--fix" ]]; then
  "$qtbin/qmlformat" -i "$here"/shell.qml "$here"/ui/*.qml
else
  for f in "$here"/shell.qml "$here"/ui/*.qml; do
    if ! "$qtbin/qmlformat" "$f" | diff -q - "$f" > /dev/null; then
      echo "qmlformat: ${f#"$here"/} is not formatted (store/tools/qmllint.sh --fix)" >&2
      status=1
    fi
  done
fi
exit $status
