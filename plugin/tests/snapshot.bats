#!/usr/bin/env bats
# `update`: fetch + ssh-keygen -Y verify + expiry + anti-rollback (ADR-0028).

load helpers

setup() {
  setup_env
  make_remote test/safe-clock test.safe-clock
  make_remote test/caution-mail test.caution-mail
}

@test "no shipped production key yet: every snapshot is refused without dev trust" {
  make_snapshot
  run "${CLI}" update "file://${SNAP}/store.json"
  [ "${status}" -eq 4 ]
  [[ ${output} == *"no trusted signing key yet"* ]]
  [ ! -e "${HOME}/.cache/omarchy-plugin-check/store.json" ]
}

@test "a production-signed snapshot verifies without dev mode" {
  trust_as_production
  make_snapshot
  run "${CLI}" update "file://${SNAP}/store.json"
  [ "${status}" -eq 0 ]
  [[ ${output} == *"snapshot verified · version 1000"* ]]
  [ "$(jq .version "${HOME}/.local/state/omarchy-plugin-check/state.json")" -eq 1000 ]
  [ -s "${HOME}/.cache/omarchy-plugin-check/index.json" ]
}

@test "a plain path and OPC_SNAPSHOT_URL work as sources" {
  trust_as_production
  make_snapshot
  run "${CLI}" update "${SNAP}/store.json"
  [ "${status}" -eq 0 ]
  make_snapshot 1001
  OPC_SNAPSHOT_URL="file://${SNAP}/store.json" run "${CLI}" update
  [ "${status}" -eq 0 ]
  [[ ${output} == *"version 1001"* ]]
}

@test "the dev key is accepted only with OPC_DEV_KEYS=1" {
  make_snapshot 1000 "" true
  OPC_DEV_SIGNERS="${DEV_SIGNERS}" run "${CLI}" update "file://${SNAP}/store.json"
  [ "${status}" -eq 4 ]
  trust_as_dev
  run "${CLI}" update "file://${SNAP}/store.json"
  [ "${status}" -eq 0 ]
  [[ ${output} == *"dev key"* ]]
}

@test "a dev:true snapshot is refused under the production key alone" {
  trust_as_production
  make_snapshot 1000 "" true
  run "${CLI}" update "file://${SNAP}/store.json"
  [ "${status}" -eq 4 ]
  [[ ${output} == *"development snapshot"* ]]
}

@test "a tampered snapshot is rejected and the last accepted one is kept" {
  trust_as_dev
  make_snapshot
  "${CLI}" update "file://${SNAP}/store.json"
  sed -i 's/"combined": "blocked"/"combined": "safe"/' "${SNAP}/store.json"
  run "${CLI}" update "file://${SNAP}/store.json"
  [ "${status}" -eq 4 ]
  [[ ${output} == *"store.json does not match the signed manifest"* ]]
  rm "${SNAP}/store-manifest.json"
  run "${CLI}" update "file://${SNAP}/store.json"
  [ "${status}" -eq 4 ]
  [[ ${output} == *"bad signature (store.json)"* ]]
  run jq -r '.plugins[] | select(.id == "io.github.example-fixtures.blocked-widget") | .verdict.combined' \
    "${HOME}/.cache/omarchy-plugin-check/store.json"
  [ "${output}" = blocked ]
}

@test "an expired snapshot is rejected" {
  trust_as_dev
  make_snapshot 1000 "$(date -u -d '-1 minute' +%FT%TZ)"
  run "${CLI}" update "file://${SNAP}/store.json"
  [ "${status}" -eq 4 ]
  [[ ${output} == *"expired at"* ]]
}

@test "a rollback to an older version is rejected; the same version is idempotent" {
  trust_as_dev
  make_snapshot 2000
  "${CLI}" update "file://${SNAP}/store.json"
  run "${CLI}" update "file://${SNAP}/store.json"
  [ "${status}" -eq 0 ]
  make_snapshot 1999
  run "${CLI}" update "file://${SNAP}/store.json"
  [ "${status}" -eq 4 ]
  [[ ${output} == *"rollback: version 1999 is older than the accepted 2000"* ]]
  [ "$(jq .version "${HOME}/.cache/omarchy-plugin-check/store.json")" -eq 2000 ]
}

@test "a cached snapshot that expires later stops being trusted" {
  trust_as_dev
  make_snapshot 1000 "$(date -u -d '+3 seconds' +%FT%TZ)"
  "${CLI}" update "file://${SNAP}/store.json"
  sleep 4
  run "${CLI}" test.safe-clock
  [ "${status}" -eq 4 ]
  [[ ${output} == *"expired"* ]]
}

@test "plain http sources are refused" {
  trust_as_dev
  run "${CLI}" update "http://example.invalid/store.json"
  [ "${status}" -ne 0 ]
  [[ ${output} == *"refusing a plain http"* ]]
}

@test "client bundle: manifest verified, every listed file fetched and checked, version shared with the store" {
  trust_as_dev
  make_snapshot 1500
  run "${CLI}" update "file://${SNAP}/store-manifest.json"
  [ "${status}" -eq 0 ]
  [[ ${output} == *"version 1500"*"client bundle"* ]]
  local c="${HOME}/.cache/omarchy-plugin-check"
  cmp "${c}/store-manifest.json" "${SNAP}/store-manifest.json"
  cmp "${c}/store-details.json" "${SNAP}/store-details.json"
  [ "$(cat "${HOME}/.local/state/omarchy-plugin-check/store-bundle-version")" = 1500 ]
  [ -L "${c}/api/v1" ]
}

@test "client bundle: the store app's accepted version also blocks a rollback" {
  trust_as_dev
  mkdir -p "${HOME}/.local/state/omarchy-plugin-check"
  echo 2000 > "${HOME}/.local/state/omarchy-plugin-check/store-bundle-version"
  make_snapshot 1999
  run "${CLI}" update "${SNAP}"
  [ "${status}" -eq 4 ]
  [[ ${output} == *"rollback: version 1999 is older than the accepted 2000"* ]]
}

@test "client bundle: a listed file that differs, or a path that escapes, is refused" {
  trust_as_dev
  make_snapshot
  echo '{}' > "${SNAP}/store-details.json"
  run "${CLI}" update "${SNAP}/store-manifest.json"
  [ "${status}" -eq 4 ]
  [[ ${output} == *"store-details.json does not match the signed manifest"* ]]
  make_snapshot
  jq '.files[0].path = "../evil.json"' "${SNAP}/store-manifest.json" > "${SNAP}/m" && mv "${SNAP}/m" "${SNAP}/store-manifest.json"
  rm "${SNAP}/store-manifest.json.sig"
  ssh-keygen -q -Y sign -f "${KEY}" -n omarchy-plugin-check-snapshot "${SNAP}/store-manifest.json"
  run "${CLI}" update "${SNAP}/store-manifest.json"
  [ "${status}" -eq 4 ]
  [[ ${output} == *"bad manifest entry ../evil.json"* ]]
  [ ! -e "${BATS_TEST_TMPDIR}/evil.json" ]
}

@test "client bundle: a cached store.json edited after update is no longer trusted" {
  trust_as_dev
  make_snapshot
  "${CLI}" update "${SNAP}"
  sed -i 's/"combined": "blocked"/"combined": "safe"/' "${HOME}/.cache/omarchy-plugin-check/store.json"
  run "${CLI}" io.github.example-fixtures.blocked-widget
  [ "${status}" -eq 4 ]
  [[ ${output} == *"does not match the signed manifest"* ]]
}

@test "a bare snapshot (no manifest) replaces an older bundle cleanly" {
  trust_as_dev
  make_snapshot 1000
  "${CLI}" update "${SNAP}"
  LEGACY=1 make_snapshot 1001
  run "${CLI}" update "${SNAP}/store.json"
  [ "${status}" -eq 0 ]
  [ ! -e "${HOME}/.cache/omarchy-plugin-check/store-manifest.json" ]
  run "${CLI}" test.safe-clock
  [ "${status}" -eq 0 ]
}
