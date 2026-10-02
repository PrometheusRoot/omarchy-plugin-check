#!/usr/bin/env bats
# `pin <id>`: move an installed checkout to the snapshot's reviewed commit (ADR-0035), the
# re-pin that `omarchy plugin update` cannot do (it fast-forwards to unreviewed upstream HEAD).

load helpers

setup() {
  setup_env
  standard_world
  P="${HOME}/.config/omarchy/plugins"
}

head_of() { git -C "${P}/$1" rev-parse HEAD; }

# A new upstream commit, reviewed by a new snapshot.
review_new_commit() {
  move_upstream test/safe-clock
  make_snapshot "${1:-1001}"
  "${CLI}" update "file://${SNAP}/store.json" > /dev/null
  : > "${FAKE_LOG}"
}

@test "update: a newer reviewed commit; diff summary, verdict change, checkout, rescan, log" {
  local old
  "${CLI}" --add --pin --yes test.safe-clock > /dev/null
  old=$(head_of test.safe-clock)
  printf '# Local Omarchy changes\n\n---\n' > "${HOME}/.config/omarchy/CHANGES.md"
  review_new_commit
  run "${CLI}" pin --yes test.safe-clock
  [ "${status}" -eq 0 ]
  [ "$(head_of test.safe-clock)" = "$(remote_commit test/safe-clock)" ]
  [[ ${output} == *"[1/6] verify snapshot signature"*"[6/6] log to"* ]]
  [[ ${output} == *"test.safe-clock  ${old:0:7} → $(remote_commit test/safe-clock | cut -c1-7)  forward 1 commit(s)"* ]]
  [[ ${output} == *"verdict  safe (pinned $(date -u +%F)) → safe"* ]]
  [[ ${output} == *"files    1 file changed, 1 insertion(+)"*"M  Widget.qml"* ]]
  [[ ${output} == *"✓ pinned test.safe-clock ${old:0:7} → $(remote_commit test/safe-clock | cut -c1-7) (tree =) · safe · logged"* ]]
  grep -qx "git fetch https://github.com/test/safe-clock HEAD" "${FAKE_LOG}"
  grep -qx "omarchy plugin validate ${P}/test.safe-clock" "${FAKE_LOG}"
  grep -qx "omarchy-shell shell rescanPlugins" "${FAKE_LOG}"
  run cat "${HOME}/.config/omarchy/CHANGES.md"
  [[ ${output} == *"### Plugin: Safe Clock (\`test.safe-clock\`) re-pinned"*"- **Undo:** \`git -C ~/.config/omarchy/plugins/test.safe-clock checkout ${old:0:7}\`"* ]]
  [ "$(jq -r '.plugins[0] | "\(.state) \(.repin)"' "${HOME}/.cache/omarchy-plugin-check/status.json")" = "safe null" ]
  [ "$(jq -r '."test.safe-clock".commit' "${HOME}/.local/state/omarchy-plugin-check/pins.json")" = "$(remote_commit test/safe-clock)" ]
}

@test "upstream ahead but unreviewed: says stale, offers nothing, changes nothing" {
  local reviewed
  "${CLI}" --add --pin --yes test.safe-clock > /dev/null
  reviewed=$(head_of test.safe-clock)
  move_upstream test/safe-clock
  : > "${FAKE_LOG}"
  run "${CLI}" pin test.safe-clock
  [ "${status}" -eq 0 ]
  [[ ${output} == *"test.safe-clock is at the reviewed commit ${reviewed:0:7} (safe)"* ]]
  [[ ${output} == *"upstream HEAD $(remote_commit test/safe-clock | cut -c1-7) is newer but unreviewed (stale); nothing to pin"* ]]
  [ "$(head_of test.safe-clock)" = "${reviewed}" ]
  run grep -c "rescanPlugins" "${FAKE_LOG}"
  [ "${output}" = 0 ]
}

@test "roll back: HEAD past the review (unpinned add) goes back to the reviewed commit" {
  local reviewed
  reviewed=$(remote_commit test/safe-clock)
  move_upstream test/safe-clock
  "${CLI}" --add --yes test.safe-clock > /dev/null
  run "${CLI}" pin --yes test.safe-clock
  [ "${status}" -eq 0 ]
  [[ ${output} == *"back: HEAD is 1 commit(s) past the review (unreviewed)"* ]]
  [[ ${output} == *"verdict  stale: no review of $(remote_commit test/safe-clock | cut -c1-7) → safe"* ]]
  [ "$(head_of test.safe-clock)" = "${reviewed}" ]
}

@test "needs confirmation: refused non-interactively without --yes, nothing checked out" {
  "${CLI}" --add --pin --yes test.safe-clock > /dev/null
  local old
  old=$(head_of test.safe-clock)
  review_new_commit
  run "${CLI}" pin test.safe-clock
  [ "${status}" -eq 1 ]
  [[ ${output} == *"needs confirmation"*"pass --yes"* ]]
  [ "$(head_of test.safe-clock)" = "${old}" ]
}

@test "refusals: blocked 2, unlisted 3, not installed 1, untrusted only 1, no fetch" {
  make_remote example-fixtures/blocked-widget io.github.example-fixtures.blocked-widget
  git clone -q "${FAKE_REMOTES}/example-fixtures/blocked-widget.git" "${P}/io.github.example-fixtures.blocked-widget"
  git -C "${P}/io.github.example-fixtures.blocked-widget" remote set-url origin https://github.com/example-fixtures/blocked-widget
  run "${CLI}" pin --yes io.github.example-fixtures.blocked-widget
  [ "${status}" -eq 2 ]
  [[ ${output} == *"is blocked; refusing to pin it"* ]]
  make_remote someone/my-clock dev.local.my-clock
  git clone -q "${FAKE_REMOTES}/someone/my-clock.git" "${P}/dev.local.my-clock"
  run "${CLI}" pin --yes dev.local.my-clock
  [ "${status}" -eq 3 ]
  [[ ${output} == *"is unlisted"* ]]
  run "${CLI}" pin --yes test.caution-mail
  [ "${status}" -eq 1 ]
  [[ ${output} == *"not a git checkout"* ]]
  make_remote test/untrusted test.untrusted
  git clone -q "${FAKE_REMOTES}/test/untrusted.git" "${P}/test.untrusted"
  git -C "${P}/test.untrusted" remote set-url origin https://github.com/test/untrusted
  run "${CLI}" pin --yes test.untrusted
  [ "${status}" -eq 1 ]
  [[ ${output} == *"no single reviewed commit in the snapshot (unreviewed)"* ]]
  run "${CLI}" pin --yes ../etc
  [ "${status}" -eq 1 ]
  run grep -c "git fetch" "${FAKE_LOG}"
  [ "${output}" = 0 ]
}

@test "a moved checkout fetches from the listed repository, never its former origin" {
  local old
  old=$(remote_commit test/safe-clock)
  git clone -q "${FAKE_REMOTES}/test/safe-clock.git" "${P}/test.safe-clock"
  git -C "${P}/test.safe-clock" remote set-url origin https://github.com/test/old-clock.git
  review_new_commit
  run "${CLI}" pin --yes test.safe-clock
  [ "${status}" -eq 0 ]
  [[ ${output} == *"origin   https://github.com/test/old-clock.git is a former name; fetched from https://github.com/test/safe-clock"* ]]
  grep -qx "git fetch https://github.com/test/safe-clock HEAD" "${FAKE_LOG}"
  [ "$(head_of test.safe-clock)" = "$(remote_commit test/safe-clock)" ]
  [ "$(head_of test.safe-clock)" != "${old}" ]
}

@test "the reviewed commit's tree is not the attested one: refused before checkout" {
  "${CLI}" --add --pin --yes test.safe-clock > /dev/null
  local old
  old=$(head_of test.safe-clock)
  move_upstream test/safe-clock
  SAFE_TREE_OVERRIDE=4444444444444444444444444444444444444444 make_snapshot 1001
  "${CLI}" update "file://${SNAP}/store.json" > /dev/null
  run "${CLI}" pin --yes test.safe-clock
  [ "${status}" -eq 1 ]
  [[ ${output} == *"does not have the attested tree 4444444"* ]]
  [ "$(head_of test.safe-clock)" = "${old}" ]
}

@test "offline: pin refuses to run" {
  "${CLI}" --add --pin --yes test.safe-clock > /dev/null
  review_new_commit
  OPC_OFFLINE=1 run "${CLI}" pin --yes test.safe-clock
  [ "${status}" -eq 1 ]
  [[ ${output} == *"not with OPC_OFFLINE=1"* ]]
}
