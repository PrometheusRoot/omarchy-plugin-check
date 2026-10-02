#!/usr/bin/env bash
# Launch the store through its launcher (floating 1280x800), wait, screenshot the window
# with grim, close it. Dev aid for docs and reviews.
#   store/tools/shot.sh OUT.png [seconds] [--dev]
#   STORE_KEYS="2 w e a" store/tools/shot.sh ...   sends keys before the shot
set -euo pipefail
out=$(realpath -m "$1")
wait=${2:-6}
here=$(cd "$(dirname "$0")/.." && pwd)
log=${out%.png}.log
title="omarchy plugin store"
"$here/bin/omarchy-plugin-store" "${@:3}" > "$log" 2>&1 &
sleep "$wait"
addr=$(hyprctl clients -j | jq -r --arg t "$title" '.[] | select(.title == $t) | .address' | head -1)
if [[ -z $addr ]]; then
  echo "store window not found" >&2
  exit 1
fi
if [[ -n ${STORE_KEYS:-} ]]; then
  hyprctl dispatch "hl.dsp.focus({ window = \"address:$addr\" })" > /dev/null 2>&1 \
    || hyprctl dispatch focuswindow "address:$addr" > /dev/null
  sleep 0.3
fi
# Keys go to the focused store window via wtype: names (Return, Escape, Down) or text.
for k in ${STORE_KEYS:-}; do
  case $k in
    Return | Escape | Down | Up | Left | Right | Tab | BackSpace) wtype -k "$k" ;;
    *) wtype -- "$k" ;;
  esac
  sleep 0.35
done
[[ -n ${STORE_KEYS:-} ]] && sleep "${STORE_SETTLE:-1.5}"
geo=$(hyprctl clients -j | jq -r --arg a "$addr" '.[] | select(.address == $a) | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')
grim -g "$geo" "$out"
echo "$out ($geo)"
if [[ -z ${STORE_KEEP:-} ]]; then
  hyprctl dispatch "hl.dsp.window.close({ window = \"address:$addr\" })" > /dev/null 2>&1 \
    || hyprctl dispatch closewindow "address:$addr" > /dev/null
fi
