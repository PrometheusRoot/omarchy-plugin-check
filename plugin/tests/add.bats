#!/usr/bin/env bats
# `--add`: the gate in front of `omarchy plugin add` (mockup "--add refusal", "--add on a
# stale plugin"). The fake `omarchy` records every call in ${FAKE_LOG}.

load helpers

setup() {
  setup_env
  standard_world
  : > "${FAKE_LOG}"
}

installed() { echo "${HOME}/.config/omarchy/plugins/$1"; }

@test "blocked: refused with exit 2, hard-fails listed, omarchy never called" {
  run "${CLI}" --add https://github.com/example-fixtures/blocked-widget
  [ "${status}" -eq 2 ]
  [[ ${output} == *"⊘ blocked  Weather Pro  io.github.example-fixtures.blocked-widget"* ]]
  [[ ${output} == *"hard-fails 6"* ]]
  [[ ${output} == *"exec         remote script piped to shell"*"BarWidget.qml:21"* ]]
  [[ ${output} == *"✗ refusing to run omarchy plugin add. --force is not honored for blocked plugins."* ]]
  run grep -c "^omarchy" "${FAKE_LOG}"
  [ "${output}" = 0 ]
}

@test "blocked: --force --yes --pin still refuse" {
  run "${CLI}" --add --force --yes --pin --enable io.github.example-fixtures.blocked-widget
  [ "${status}" -eq 2 ]
  run grep -c "^omarchy" "${FAKE_LOG}"
  [ "${output}" = 0 ]
}

@test "retired: refused with exit 2; not installable and built-in: exit 1" {
  run "${CLI}" --add --yes test.retired
  [ "${status}" -eq 2 ]
  [[ ${output} == *"retired from plugins.omarchy.org"* ]]
  run "${CLI}" --add --yes test.manual
  [ "${status}" -eq 1 ]
  run "${CLI}" --add --yes omarchy.clock
  [ "${status}" -eq 1 ]
  run grep -c "plugin add" "${FAKE_LOG}"
  [ "${output}" = 0 ]
}

@test "caution needs confirmation: refused non-interactively without --yes" {
  run "${CLI}" --add test.caution-mail
  [ "${status}" -eq 1 ]
  [[ ${output} == *"needs confirmation"*"pass --yes"* ]]
  [ ! -e "$(installed test.caution-mail)" ]
}

@test "safe + --pin --enable --yes: cloned, pinned to the attested commit and tree, enabled" {
  run "${CLI}" --add --pin --enable --yes https://github.com/test/safe-clock
  [ "${status}" -eq 0 ]
  local d
  d=$(installed test.safe-clock)
  [ "$(git -C "${d}" rev-parse HEAD)" = "$(remote_commit test/safe-clock)" ]
  [ "$(git -C "${d}" rev-parse 'HEAD^{tree}')" = "$(remote_tree test/safe-clock)" ]
  [[ ${output} == *"[1/6] verify snapshot signature"*"[6/6] log to"* ]]
  [[ ${output} == *"✓ cloned · pinned $(remote_commit test/safe-clock | cut -c1-7) (tree =) · enabled"* ]]
  grep -qx "omarchy plugin add https://github.com/test/safe-clock --yes" "${FAKE_LOG}"
  grep -qx "omarchy plugin enable test.safe-clock" "${FAKE_LOG}"
}

@test "safe without --pin passes --enable straight to omarchy plugin add" {
  run "${CLI}" --add --enable test.safe-clock
  [ "${status}" -eq 0 ]
  grep -qx "omarchy plugin add https://github.com/test/safe-clock --yes --enable" "${FAKE_LOG}"
}

@test "stale: upstream moved; --pin checks out the reviewed commit, not upstream HEAD" {
  local reviewed
  reviewed=$(remote_commit test/safe-clock)
  move_upstream test/safe-clock
  run "${CLI}" --add test.safe-clock
  [ "${status}" -eq 1 ]
  [[ ${output} == *"◷ stale"* ]]
  run "${CLI}" --add --pin --yes test.safe-clock
  [ "${status}" -eq 0 ]
  [ "$(git -C "$(installed test.safe-clock)" rev-parse HEAD)" = "${reviewed}" ]
}

@test "pinned checkout whose tree differs from the attested tree is rolled back" {
  SAFE_TREE_OVERRIDE=4444444444444444444444444444444444444444 make_snapshot 1001
  "${CLI}" update "file://${SNAP}/store.json"
  : > "${FAKE_LOG}"
  run "${CLI}" --add --pin --yes test.safe-clock
  [ "${status}" -eq 1 ]
  [[ ${output} == *"does not match the attested subject"* ]]
  grep -qx "omarchy plugin remove test.safe-clock --yes" "${FAKE_LOG}"
  [ ! -e "$(installed test.safe-clock)" ]
}

@test "reviewed commit missing upstream (force-push): rolled back" {
  local work="${BATS_TEST_TMPDIR}/work/test/caution-mail"
  git -C "${work}" commit -q --amend -m rewritten
  git -C "${work}" push -q -f "${FAKE_REMOTES}/test/caution-mail.git" main
  git --git-dir "${FAKE_REMOTES}/test/caution-mail.git" gc -q --prune=now
  run "${CLI}" --add --pin --yes test.caution-mail
  [ "${status}" -eq 1 ]
  [[ ${output} == *"not in the upstream repository"* ]]
  [ ! -e "$(installed test.caution-mail)" ]
}

@test "unlisted URL: confirm, nothing pinned; --yes adds it from that URL" {
  make_remote someone/my-clock dev.local.my-clock
  run "${CLI}" --add https://github.com/someone/my-clock
  [ "${status}" -eq 1 ]
  [[ ${output} == *"◌ unlisted"* ]]
  run "${CLI}" --add --pin --yes https://github.com/someone/my-clock
  [ "${status}" -eq 0 ]
  [[ ${output} == *"unlisted: nothing reviewed, so nothing to pin"* ]]
  [ -d "$(installed dev.local.my-clock)" ]
}

@test "an unknown plain id is not a URL: exit 3, nothing cloned" {
  run "${CLI}" --add --yes no.such.plugin
  [ "${status}" -eq 3 ]
  run grep -c "plugin add" "${FAKE_LOG}"
  [ "${output}" = 0 ]
}

@test "a transport-helper URL is refused before anything runs" {
  run "${CLI}" --add --yes 'ext::sh -c touch% /tmp/pwned'
  [ "${status}" -ne 0 ]
  run grep -c "plugin add" "${FAKE_LOG}"
  [ "${output}" = 0 ]
}

@test "a suite repository asks for the id" {
  run "${CLI}" --add --yes https://github.com/test/suite
  [ "${status}" -eq 1 ]
  [[ ${output} == *"lists 2 plugins (test.suite-a, test.suite-b); pass the id"* ]]
}

@test "no verified snapshot: exit 4; --force adds it as unreviewed but cannot pin" {
  rm -rf -- "${HOME}/.cache/omarchy-plugin-check"
  run "${CLI}" --add --yes test.safe-clock
  [ "${status}" -eq 4 ]
  run "${CLI}" --add --force --pin --yes https://github.com/test/safe-clock
  [ "${status}" -eq 4 ]
  run "${CLI}" --add --force --yes https://github.com/test/safe-clock
  [ "${status}" -eq 0 ]
  [ -d "$(installed test.safe-clock)" ]
}

@test "CHANGES.md: an entry under today's date in the file's own format; absent file stays absent" {
  run "${CLI}" --add --pin --yes test.safe-clock
  [ ! -e "${HOME}/.config/omarchy/CHANGES.md" ]
  "${omarchy:-omarchy}" plugin remove test.safe-clock
  printf '# Local Omarchy changes\n\nNewest first.\n\n---\n\n## 2026-01-01\n\n### Old entry\n' > "${HOME}/.config/omarchy/CHANGES.md"
  run "${CLI}" --add --pin --yes test.safe-clock
  [ "${status}" -eq 0 ]
  [[ ${output} == *"logged to ~/.config/omarchy/CHANGES.md"* ]]
  run cat "${HOME}/.config/omarchy/CHANGES.md"
  [[ ${output} == *$'---\n\n## '"$(date +%F)"$'\n\n### Plugin: Safe Clock (`test.safe-clock`)\n- **Source:** https://github.com/test/safe-clock — commit `'* ]]
  [[ ${output} == *'(pinned to the reviewed commit, detached HEAD; update with `omarchy-plugin-check pin test.safe-clock`, not `omarchy plugin update`'* ]]
  [[ ${output} == *"- **Reviewed:** safe per omarchy-plugin-check (reviewed commit"* ]]
  [[ ${output} == *'- **Undo:** `omarchy plugin remove test.safe-clock`'$'\n\n## 2026-01-01'* ]]
}

@test "already installed: refused before cloning" {
  "${CLI}" --add --yes test.safe-clock
  : > "${FAKE_LOG}"
  run "${CLI}" --add --yes test.safe-clock
  [ "${status}" -eq 1 ]
  [[ ${output} == *"already installed"* ]]
  run grep -c "plugin add" "${FAKE_LOG}"
  [ "${output}" = 0 ]
}
