#!/usr/bin/env bats
# `omarchy-plugin-check <git-url|id>`: the verdict card (mockup "cli · verdict card").

load helpers

setup() {
  setup_env
  standard_world
}

@test "no snapshot: exit 4 with the reason" {
  rm -rf -- "${HOME}/.cache/omarchy-plugin-check"
  run "${CLI}" test.safe-clock
  [ "${status}" -eq 4 ]
  [[ ${output} == *"no verified snapshot"* ]]
}

@test "safe plugin by URL: card with providers, criteria, commit = upstream, snapshot badge" {
  run "${CLI}" https://github.com/test/safe-clock
  [ "${status}" -eq 0 ]
  [[ ${output} == *"╭─ Safe Clock · test.safe-clock"* ]]
  [[ ${output} == *"✓ safe  combined · worst of 1 trusted"* ]]
  [[ ${output} == *"opc ✓ safe core ✓sig"* ]]
  [[ ${output} == *"marketplace ✓ safe unsigned ○unsigned ≤caution"* ]]
  [[ ${output} == *"✓safe-to-run ✓no-network ✓no-exec ·reviewed-by-human"* ]]
  [[ ${output} == *"$(remote_commit test/safe-clock | cut -c1-7)  = upstream"* ]]
  [[ ${output} == *"snap   ✓ verified · 1h old · catalog 10-01"* ]]
  [[ ${output} == *"↗ https://plugins.omarchy.org/plugin.html?id=test.safe-clock"* ]]
  grep -q "git ls-remote -- https://github.com/test/safe-clock HEAD" "${FAKE_LOG}"
}

@test "URL spellings resolve to the same listing" {
  local u
  for u in https://github.com/Test/Safe-Clock.git git@github.com:test/safe-clock.git \
    ssh://git@github.com/test/safe-clock https://github.com/test/safe-clock/ test.safe-clock; do
    run "${CLI}" "${u}"
    [ "${status}" -eq 0 ]
    [[ ${output} == *"Safe Clock · test.safe-clock"* ]]
  done
}

@test "upstream moved past the reviewed commit: stale, with the reviewed outcome" {
  move_upstream test/safe-clock
  run "${CLI}" test.safe-clock
  [ "${status}" -eq 0 ]
  [[ ${output} == *"◷ stale  reviewed ✓ safe at"* ]]
  [[ ${output} == *"≠ upstream $(remote_commit test/safe-clock | cut -c1-7) (moved, unreviewed)"* ]]
}

@test "offline: no ls-remote, upstream unknown, verdict still shown" {
  OPC_OFFLINE=1 run "${CLI}" test.safe-clock
  [ "${status}" -eq 0 ]
  [[ ${output} == *"✓ safe"* ]]
  [[ ${output} == *"upstream ? (offline)"* ]]
  run grep -c ls-remote "${FAKE_LOG}"
  [ "${output}" = 0 ]
}

@test "unlisted URL: warning, exit 3 (mockup)" {
  run "${CLI}" https://github.com/someone/my-clock
  [ "${status}" -eq 3 ]
  [[ ${output} == *"◌ unlisted  not on plugins.omarchy.org · no provider has reviewed it"* ]]
  [[ ${output} == *"no verdict. --add will ask for confirmation; nothing is pinned."* ]]
}

@test "blocked plugin card lists its hard-fails and the contested flag shows" {
  run "${CLI}" https://github.com/example-fixtures/blocked-widget
  [ "${status}" -eq 0 ]
  [[ ${output} == *"⊘ blocked"* ]]
  [[ ${output} == *"6 blocking"* ]]
  [[ ${output} == *"remote script piped to shell  BarWidget.qml:21"* ]]
  run "${CLI}" test.risky-bar
  [[ ${output} == *"◆ risky"* && ${output} == *"⚑ contested"* ]]
}

@test "an installed checkout shows local commit/tree against the reviewed ones" {
  git clone -q "${FAKE_REMOTES}/test/safe-clock.git" "${HOME}/.config/omarchy/plugins/test.safe-clock"
  git -C "${HOME}/.config/omarchy/plugins/test.safe-clock" remote set-url origin https://github.com/test/safe-clock.git
  run "${CLI}" test.safe-clock
  [[ ${output} == *"local  $(remote_commit test/safe-clock | cut -c1-7)  commit =  tree ="* ]]
}

@test "a suite repository prints one card per listed plugin" {
  run "${CLI}" https://github.com/test/suite
  [ "${status}" -eq 0 ]
  [[ ${output} == *"Suite A · test.suite-a"* && ${output} == *"Suite B · test.suite-b"* ]]
}

@test "untrusted-only and retired rows" {
  run "${CLI}" test.untrusted
  [[ ${output} == *"? unreviewed  no trusted review · untrusted rows only"* ]]
  run "${CLI}" test.retired
  [[ ${output} == *"▭ retired"* ]]
}

@test "nerd font glyphs by default, colour only on request" {
  OPC_GLYPHS=nerd OPC_COLOR=always run "${CLI}" test.safe-clock
  [[ ${output} == *$'\e[32m'* ]]
  [[ ${output} == *"$(printf '\U000F0CC8') safe"* ]]
}
