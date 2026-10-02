#!/usr/bin/env bash
# Lint the plugin: shellcheck (enable=all, .shellcheckrc), shfmt, qmllint, qmlformat, and
# `omarchy plugin validate` when Omarchy is installed. `--fix` formats in place.
# Quickshell serves its config dir as the `qs` module; a temp import path with qs -> the
# Omarchy shell gives qmllint the host's qs.Commons / qs.Ui (OMARCHY_SHELL overrides it).
set -Eeuo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
qtbin=${QT_BIN:-/usr/lib/qt6/bin}
qml=${QML_IMPORT_PATH:-/usr/lib/qt6/qml}
omarchy_shell=${OMARCHY_SHELL:-/usr/share/omarchy/shell}
tmp=$(mktemp -d)
trap 'rm -rf -- "${tmp}"' EXIT
status=0
shells=("${here}/bin/omarchy-plugin-check" "${here}/tools/lint.sh" "${here}/tests/helpers.bash" "${here}"/tests/bin/* "${here}"/tests/*.bats)
qmls=("${here}/Panel.qml" "${here}/BarWidget.qml")

if [[ ${1:-} == --fix ]]; then
  shfmt -w -i 2 -ci -bn -sr "${shells[@]}"
  "${qtbin}/qmlformat" -i "${qmls[@]}"
fi

shellcheck -x "${shells[@]}" || status=1
shfmt -d -i 2 -ci -bn -sr "${shells[@]}" || status=1

if [[ -d ${omarchy_shell} ]]; then
  ln -s -- "${omarchy_shell}" "${tmp}/qs"
  # Filtered false positives, each also reported on Omarchy's own panels:
  #   [uncreatable-type] "Type PanelWindow is not creatable" + the [unqualified]/[unresolved-type]
  #     `margins` group that follows from it  # why: Quickshell 0.3.1's qmltypes export
  #     PanelWindow as uncreatable; it is the documented layer-shell window and runs.
  #   [signal-handler-parameters] "QProcess::ExitStatus ... onExited"  # why: Quickshell's
  #     Process.exited names a QtCore enum its qmltypes do not export (same filter as store/).
  "${qtbin}/qmllint" -I "${tmp}" -I "${qml}" "${qmls[@]}" > "${tmp}/lint.txt" 2>&1 || true
  grep -E "^(Warning|Error)" "${tmp}/lint.txt" \
    | grep -v -e "Type PanelWindow is not creatable" -e "grouped property scope margins" \
      -e "Type margins is used but it is not resolved" \
      -e "Type QProcess::ExitStatus of parameter exitStatus in signal called exited" > "${tmp}/issues.txt" || true
  if [[ -s ${tmp}/issues.txt ]]; then
    cat -- "${tmp}/lint.txt" >&2
    echo "qmllint: $(wc -l < "${tmp}/issues.txt") issue(s)" >&2
    status=1
  fi
else
  echo "qmllint: skipped (no Omarchy shell at ${omarchy_shell})" >&2
fi

for f in "${qmls[@]}"; do
  if ! "${qtbin}/qmlformat" "${f}" | diff -q - "${f}" > /dev/null; then
    echo "qmlformat: ${f#"${here}"/} is not formatted (tools/lint.sh --fix)" >&2
    status=1
  fi
done

if command -v omarchy-plugin-validate > /dev/null; then
  omarchy-plugin-validate "${here}" || status=1
fi
exit "${status}"
