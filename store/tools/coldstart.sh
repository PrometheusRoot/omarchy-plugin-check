#!/usr/bin/env bash
# Cold start, as the app logs it (all times from launch, OPC_STORE_T0):
#   first frame  - first rendered frame
#   home         - home tab has content (disk cache, or the worker on a cold cache)
#   parse/map    - JSON.parse + adapter in the worker (QV4), after the first frame
#   searchable   - index built in the worker
#   store/tools/coldstart.sh [runs] [config dir] [--dev] [--cold]
# --cold deletes the home cache first. OPC_STORE_SNAPSHOT=path selects a snapshot.
set -euo pipefail
runs=${1:-5}
dir=${2:-$(cd "$(dirname "$0")/.." && pwd)}
[[ " $* " == *" --dev "* ]] && export OPC_STORE_DEV=1
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
num() { grep -o "$1 [0-9]*" "$tmp/log" | head -1 | grep -o "[0-9]*$" || echo "?"; }
for i in $(seq 1 "$runs"); do
  [[ " $* " == *" --cold "* ]] && rm -f "$HOME/.cache/omarchy-plugin-check/store-home.json"
  OPC_STORE_T0=$(date +%s%3N)
  export OPC_STORE_T0
  qs -p "$dir" > "$tmp/log" 2>&1 &
  pid=$!
  for _ in $(seq 1 600); do
    grep -q "searchable at" "$tmp/log" && break
    sleep 0.05
  done
  kill "$pid" 2> /dev/null || true
  wait "$pid" 2> /dev/null || true
  echo "run $i: first frame $(num "first frame") ms · home $(num "home ready") ms · parse $(num "parse") ms map $(num "map") ms (worker) · index $(num "store: index") ms · searchable $(num "searchable at") ms"
done
