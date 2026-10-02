#!/usr/bin/env bash
# Cold start, as the app logs it (all times from launch, OPC_STORE_T0; ADR-0031, ADR-0032):
#   first frame  - first rendered frame
#   verified     - bundle verification finished (manifest signature + sha256 of every file)
#   home         - home tab has content (home slice parsed + mapped on the GUI thread)
#   parse/map    - search columns: JSON.parse + adapter in the worker (QV4), after the first frame
#   searchable   - index built in the worker
#   bench        - with --bench: in-app search latency (QV4 worker) once warm, p50/p95 per keystroke
#   store/tools/coldstart.sh [runs] [config dir] [--dev] [--bench]
# OPC_STORE_BUNDLE=dir selects a bundle (a DEV-key bundle also needs OPC_STORE_DEV_KEYS=1).
set -euo pipefail
runs=${1:-5}
dir=${2:-$(cd "$(dirname "$0")/.." && pwd)}
[[ " $* " == *" --dev "* ]] && export OPC_STORE_DEV=1
wait_for="searchable at"
if [[ " $* " == *" --bench "* ]]; then
  export OPC_STORE_BENCH=1
  wait_for="store: bench"
fi
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
num() { grep -o "$1 [0-9]*" "$tmp/log" | head -1 | grep -o "[0-9]*$" || echo "?"; }
for i in $(seq 1 "$runs"); do
  OPC_STORE_T0=$(date +%s%3N)
  export OPC_STORE_T0
  qs -p "$dir" > "$tmp/log" 2>&1 &
  pid=$!
  for _ in $(seq 1 600); do
    grep -q "$wait_for" "$tmp/log" && break
    sleep 0.05
  done
  kill "$pid" 2> /dev/null || true
  wait "$pid" 2> /dev/null || true
  echo "run $i: first frame $(num "first frame") ms · verified $(num "verified bundle") ms · home $(num "home ready") ms · parse $(num "parse") ms map $(num "map") ms (worker) · index $(num "store: index") ms · searchable $(num "searchable at") ms$([[ -n ${OPC_STORE_BENCH:-} ]] && echo " · search p50 $(grep -o "p50 [0-9.]*" "$tmp/log" | head -1 | cut -d" " -f2) p95 $(grep -o "p95 [0-9.]*" "$tmp/log" | head -1 | cut -d" " -f2) ms")"
done
