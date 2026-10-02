#!/usr/bin/env bash
# Writes store/ui/qmldir (the qs.ui module: every component, singletons marked). Quickshell
# would generate the same at runtime; the committed copy lets qmllint resolve singletons.
# `just store-lint` fails if it is stale.
set -euo pipefail
ui=$(cd "$(dirname "$0")/../ui" && pwd)
{
  echo "module qs.ui"
  for f in "$ui"/*.qml; do
    n=$(basename "$f" .qml)
    if grep -q "^pragma Singleton" "$f"; then echo "singleton $n 1.0 $n.qml"; else echo "$n 1.0 $n.qml"; fi
  done
} > "${1:-$ui/qmldir}"
