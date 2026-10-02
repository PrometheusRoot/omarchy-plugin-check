#!/usr/bin/env bats
# `status [--json]`: every checkout in ~/.config/omarchy/plugins against the snapshot;
# writes ~/.cache/omarchy-plugin-check/status.json for the panel and the bar widget.

load helpers

setup() {
  setup_env
  standard_world
  P="${HOME}/.config/omarchy/plugins"
}

checkout() { # checkout OWNER/NAME DIR [ORIGIN]
  git clone -q "${FAKE_REMOTES}/$1.git" "${P}/$2"
  git -C "${P}/$2" remote set-url origin "${3:-https://github.com/$1.git}"
}

state_of() { jq -r --arg d "$1" '.plugins[] | select(.dir | endswith("/" + $d)) | .state' "${HOME}/.cache/omarchy-plugin-check/status.json"; }

@test "states: safe, stale (new commit, no attested tree), unlisted, a fork reusing a listed id" {
  checkout test/safe-clock test.safe-clock
  checkout test/caution-mail test.caution-mail
  git -C "${P}/test.caution-mail" commit -q --allow-empty -m "local commit"
  make_remote someone/my-clock dev.local.my-clock
  checkout someone/my-clock dev.local.my-clock
  # A fork that reuses a listed id must not inherit its verdict.
  make_remote evil/safe-clock test.safe-clock
  checkout evil/safe-clock fork-of-safe-clock https://github.com/evil/safe-clock.git
  run "${CLI}" status
  [ "${status}" -eq 0 ]
  [ "$(state_of test.safe-clock)" = safe ]
  # no attested tree for caution-mail, so a different commit cannot be matched by content
  [ "$(state_of test.caution-mail)" = stale ]
  [ "$(state_of dev.local.my-clock)" = unlisted ]
  [ "$(state_of fork-of-safe-clock)" = unlisted ]
  [[ ${output} == *"origin is not the listed repository of test.safe-clock"* ]]
  [[ ${output} == *"4 plugins"* ]]
  [[ ${output} == *"✓ snapshot verified · 1h old · version 1000"* ]]
}

@test "commit differs but tree matches: still the reviewed outcome (c ≠ t =)" {
  checkout test/safe-clock test.safe-clock
  git -C "${P}/test.safe-clock" commit -q --amend -m "re-signed, same content"
  run "${CLI}" status --json
  [ "${status}" -eq 0 ]
  run jq -r '.plugins[0] | "\(.state) \(.commitMatch) \(.treeMatch)"' "${HOME}/.cache/omarchy-plugin-check/status.json"
  [ "${output}" = "safe false true" ]
}

@test "commit and tree differ: stale" {
  checkout test/safe-clock test.safe-clock
  printf 'x\n' >> "${P}/test.safe-clock/Widget.qml"
  git -C "${P}/test.safe-clock" commit -q -am local
  "${CLI}" status > /dev/null
  [ "$(state_of test.safe-clock)" = stale ]
}

@test "--json writes the panel's status.json; worst and counts" {
  checkout test/safe-clock test.safe-clock
  make_remote example-fixtures/blocked-widget io.github.example-fixtures.blocked-widget
  checkout example-fixtures/blocked-widget io.github.example-fixtures.blocked-widget
  run "${CLI}" status --json
  [ "${status}" -eq 0 ]
  echo "${output}" | jq -e '.kind == "omarchy-plugin-check/status" and .worst == "blocked"
    and .counts == {"blocked": 1, "safe": 1} and .snapshot.ok == true
    and (.plugins[0].id == "io.github.example-fixtures.blocked-widget")
    and (.plugins[0].url == "https://plugins.omarchy.org/plugin.html?id=io.github.example-fixtures.blocked-widget")'
  cmp <(echo "${output}") "${HOME}/.cache/omarchy-plugin-check/status.json"
}

@test "status never fetches anything and works without a snapshot" {
  checkout test/safe-clock test.safe-clock
  rm -rf -- "${HOME}/.cache/omarchy-plugin-check" "${HOME}/.local/state/omarchy-plugin-check"
  : > "${FAKE_LOG}"
  run "${CLI}" status
  [ "${status}" -eq 0 ]
  [[ ${output} == *"? unreviewed"*"no verified snapshot"* ]]
  [ "$(jq -r .snapshot.ok "${HOME}/.cache/omarchy-plugin-check/status.json")" = false ]
  [ ! -s "${FAKE_LOG}" ]
}

@test "a hand-copied plugin (no git) is listed as stale against its listing" {
  mkdir -p "${P}/test.safe-clock"
  git --git-dir "${FAKE_REMOTES}/test/safe-clock.git" archive main | tar -x -C "${P}/test.safe-clock"
  "${CLI}" status > /dev/null
  [ "$(state_of test.safe-clock)" = stale ]
}

@test "no plugins: empty table, worst null" {
  run "${CLI}" status --json
  [ "${status}" -eq 0 ]
  echo "${output}" | jq -e '.plugins == [] and .worst == null'
}

@test "a checkout from a former repository is the listing, moved; a fork reusing the id is not" {
  checkout test/safe-clock test.safe-clock https://github.com/test/old-clock.git
  make_remote evil/old-clock test.safe-clock
  checkout evil/old-clock fork https://github.com/evil/old-clock.git
  run "${CLI}" status
  [ "${status}" -eq 0 ]
  [ "$(state_of test.safe-clock)" = safe ]
  [ "$(state_of fork)" = unlisted ]
  [[ ${output} == *"moved: listed at github.com/test/safe-clock; origin is its former repository"* ]]
  run jq -r '.plugins[] | select(.id == "test.safe-clock" and (.dir | endswith("/test.safe-clock")))
    | "\(.listedId) \(.moved) \(.repo) \(.commitMatch) \(.treeMatch)"' "${HOME}/.cache/omarchy-plugin-check/status.json"
  [ "${output}" = "test.safe-clock true https://github.com/test/safe-clock true true" ]
  # the card says so too
  run "${CLI}" test.safe-clock
  [[ ${output} == *"moved: origin github.com/test/old-clock is a former name of the listed repository"* ]]
}

@test "repin: forward when the reviewed commit is newer (or not fetched yet), back when HEAD is past it" {
  local old
  old=$(remote_commit test/safe-clock)
  move_upstream test/safe-clock
  make_snapshot 1001
  "${CLI}" update "file://${SNAP}/store.json" > /dev/null
  # behind: the reviewed commit is in the checkout, HEAD is its parent
  checkout test/safe-clock test.safe-clock
  git -C "${P}/test.safe-clock" -c advice.detachedHead=false checkout -q "${old}"
  # not fetched: cloned before the reviewed commit existed
  git clone -q "${FAKE_REMOTES}/test/caution-mail.git" "${P}/test.caution-mail"
  git -C "${P}/test.caution-mail" remote set-url origin https://github.com/test/caution-mail.git
  move_upstream test/caution-mail
  make_snapshot 1002
  "${CLI}" update "file://${SNAP}/store.json" > /dev/null
  run "${CLI}" status
  [ "${status}" -eq 0 ]
  [[ ${output} == *"test.safe-clock: reviewed update to $(remote_commit test/safe-clock | cut -c1-7) · omarchy-plugin-check pin test.safe-clock"* ]]
  run jq -r '[.plugins[] | "\(.id)=\(.repin)"] | sort | join(" ")' "${HOME}/.cache/omarchy-plugin-check/status.json"
  [ "${output}" = "test.caution-mail=forward test.safe-clock=forward" ]
  # ahead: HEAD is a local commit past the review
  git -C "${P}/test.safe-clock" checkout -q main
  printf 'x\n' >> "${P}/test.safe-clock/Widget.qml"
  git -C "${P}/test.safe-clock" commit -q -am local
  run "${CLI}" status --json
  [ "$(jq -r '.plugins[] | select(.id == "test.safe-clock") | .repin' <<< "${output}")" = back ]
  # at the reviewed commit: nothing to do
  git -C "${P}/test.safe-clock" reset -q --hard "$(remote_commit test/safe-clock)"
  run "${CLI}" status --json
  [ "$(jq -r '.plugins[] | select(.id == "test.safe-clock") | "\(.state) \(.repin)"' <<< "${output}")" = "safe null" ]
}
