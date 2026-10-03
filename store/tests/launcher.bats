#!/usr/bin/env bats
# bin/omarchy-store: single instance (focus the open window), else qs -n -p <store dir>,
# then float + size + center once the window maps (ADR-0042). Fake hyprctl and qs only.

setup() {
  TESTS=$(cd -- "$(dirname -- "${BATS_TEST_FILENAME}")" && pwd)
  STORE=$(cd -- "${TESTS}/.." && pwd)
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}/.local/bin"
  export PATH="${TESTS}/bin:${PATH}"
  export FAKE_LOG="${BATS_TEST_TMPDIR}/calls.log" FAKE_CLIENTS="${BATS_TEST_TMPDIR}/clients.json"
  : > "${FAKE_LOG}"
  : > "${FAKE_CLIENTS}"
  unset OPC_STORE_DEV
}

@test "an open store window is focused, no second Quickshell starts" {
  echo '[{"address": "0x1", "title": "other"}, {"address": "0xabc", "title": "omarchy-store"}]' > "${FAKE_CLIENTS}"
  run "${STORE}/bin/omarchy-store"
  [ "${status}" -eq 0 ]
  grep -qx 'hyprctl dispatch hl.dsp.focus({ window = "address:0xabc" })' "${FAKE_LOG}"
  run grep -c '^qs ' "${FAKE_LOG}"
  [ "${output}" -eq 0 ]
}

@test "no window: qs -n -p <store dir>, then float, size and center it" {
  run "${STORE}/bin/omarchy-store"
  [ "${status}" -eq 0 ]
  grep -qx "qs -n -p ${STORE} dev=" "${FAKE_LOG}"
  grep -q 'hl.dsp.window.float({ window = "address:0xabc", action = "toggle" })' "${FAKE_LOG}"
  grep -q 'hl.dsp.window.resize({ window = "address:0xabc", x = 1280, y = 800 })' "${FAKE_LOG}"
  grep -q 'hl.dsp.window.center({ window = "address:0xabc" })' "${FAKE_LOG}"
  run grep -c 'hl.dsp.focus' "${FAKE_LOG}"
  [ "${output}" -eq 0 ]
}

@test "a second launch after the first focuses instead of starting again" {
  "${STORE}/bin/omarchy-store"
  "${STORE}/bin/omarchy-store"
  [ "$(grep -c '^qs ' "${FAKE_LOG}")" -eq 1 ]
  grep -q 'hl.dsp.focus({ window = "address:0xabc" })' "${FAKE_LOG}"
}

@test "through a ~/.local/bin link it still runs the store next to the launcher" {
  ln -s "${STORE}/bin/omarchy-store" "${HOME}/.local/bin/omarchy-store"
  "${HOME}/.local/bin/omarchy-store"
  grep -qx "qs -n -p ${STORE} dev=" "${FAKE_LOG}"
}

@test "--dev reaches the app as OPC_STORE_DEV=1, not as a qs argument" {
  "${STORE}/bin/omarchy-store" --dev
  grep -qx "qs -n -p ${STORE} dev=1" "${FAKE_LOG}"
}

@test "without Hyprland (hyprctl fails) it still starts the app and returns" {
  mkdir -p "${BATS_TEST_TMPDIR}/nohypr"
  printf '#!/bin/sh\necho "HYPRLAND_INSTANCE_SIGNATURE not set!"\nexit 1\n' > "${BATS_TEST_TMPDIR}/nohypr/hyprctl"
  chmod +x "${BATS_TEST_TMPDIR}/nohypr/hyprctl"
  run env PATH="${BATS_TEST_TMPDIR}/nohypr:${PATH}" "${STORE}/bin/omarchy-store"
  [ "${status}" -eq 0 ]
  grep -qx "qs -n -p ${STORE} dev=" "${FAKE_LOG}"
}
