# Shared bats setup: a throwaway HOME, fake `omarchy` + `git ls-remote`, local "GitHub"
# remotes and a fixture snapshot signed with a key generated for the test.
# shellcheck shell=bash

TESTS=$(cd -- "$(dirname -- "${BATS_TEST_FILENAME}")" && pwd)
ROOT=$(cd -- "${TESTS}/.." && pwd)

setup_env() {
  REAL_GIT=$(command -v git)
  export REAL_GIT
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p -- "${HOME}/.config/omarchy/plugins"
  unset XDG_CACHE_HOME XDG_STATE_HOME XDG_CONFIG_HOME OPC_SNAPSHOT_URL OPC_OFFLINE OPC_DEV_KEYS OPC_DEV_SIGNERS
  export FAKE_LOG="${BATS_TEST_TMPDIR}/calls.log"
  : > "${FAKE_LOG}"
  export FAKE_REMOTES="${BATS_TEST_TMPDIR}/remotes"
  export PATH="${TESTS}/bin:${PATH}"
  export OPC_GLYPHS=unicode OPC_COLOR=never NO_COLOR=1
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
  # A private copy, so a test can install a "production" key into keys/allowed_signers.
  PLUGIN="${BATS_TEST_TMPDIR}/plugin"
  cp -r -- "${ROOT}" "${PLUGIN}"
  CLI="${PLUGIN}/bin/omarchy-plugin-check"
  SNAP="${BATS_TEST_TMPDIR}/snap"
  KEY="${BATS_TEST_TMPDIR}/key"
  ssh-keygen -q -t ed25519 -N '' -C opc-test -f "${KEY}"
  DEV_SIGNERS="${BATS_TEST_TMPDIR}/allowed_signers.dev"
  printf 'omarchy-plugin-check namespaces="omarchy-plugin-check-snapshot" %s\n' "$(cat -- "${KEY}.pub")" > "${DEV_SIGNERS}"
}

# Trust the test key as the shipped production key (in the private plugin copy).
trust_as_production() { cat -- "${DEV_SIGNERS}" >> "${PLUGIN}/keys/allowed_signers"; }
# Trust the test key as a development key.
trust_as_dev() { export OPC_DEV_KEYS=1 OPC_DEV_SIGNERS="${DEV_SIGNERS}"; }

# make_remote OWNER/NAME ID -> bare repo with one commit holding a valid plugin.
make_remote() {
  local repo=$1 id=$2 work="${BATS_TEST_TMPDIR}/work/$1"
  mkdir -p -- "${work}"
  git -C "${work}" init -q -b main
  jq -n --arg id "${id}" '{schemaVersion: 1, id: $id, name: $id, version: "1.0.0",
    kinds: ["bar-widget"], entryPoints: {barWidget: "Widget.qml"}}' > "${work}/manifest.json"
  printf 'import QtQuick\nItem {}\n' > "${work}/Widget.qml"
  git -C "${work}" add -A
  git -C "${work}" commit -q -m init
  mkdir -p -- "${FAKE_REMOTES}/${repo%/*}"
  git clone -q --bare -- "${work}" "${FAKE_REMOTES}/${repo}.git"
}

# move_upstream OWNER/NAME -> one more (unreviewed) commit on the remote
move_upstream() {
  local work="${BATS_TEST_TMPDIR}/work/$1"
  printf '// changed\n' >> "${work}/Widget.qml"
  git -C "${work}" commit -q -am "upstream moved"
  git -C "${work}" push -q "${FAKE_REMOTES}/$1.git" main
}

remote_commit() { git --git-dir "${FAKE_REMOTES}/$1.git" rev-parse "${2:-main}"; }
remote_tree() { git --git-dir "${FAKE_REMOTES}/$1.git" rev-parse "${2:-main}^{tree}"; }

# make_snapshot [version] [expires-iso] [dev true|false] -> ${SNAP}/store.json(.sig) + api views,
# with the commits/trees of test/safe-clock and test/caution-mail at the time of the call.
make_snapshot() {
  local version=${1:-1000} expires=${2:-$(date -u -d '+7 days' +%FT%TZ)} dev=${3:-false} f
  local safe caution tree
  safe=$(remote_commit test/safe-clock)
  tree=$(remote_tree test/safe-clock)
  caution=$(remote_commit test/caution-mail)
  mkdir -p -- "${SNAP}/api/v1/plugins"
  sed -e "s/@SAFE_COMMIT@/${safe}/g" -e "s/@CAUTION_COMMIT@/${caution}/g" "${TESTS}/fixtures/store.json" \
    | jq --argjson v "${version}" --arg e "${expires}" --argjson dev "${dev}" --arg g "$(date -u -d '-1 hour' +%FT%TZ)" \
      '.version = $v | .expires = $e | .dev = $dev | .generatedAt = $g' > "${SNAP}/store.json"
  for f in "${TESTS}"/fixtures/api/*.json; do
    sed -e "s/@SAFE_COMMIT@/${safe}/g" -e "s/@SAFE_TREE@/${SAFE_TREE_OVERRIDE:-${tree}}/g" "${f}" \
      > "${SNAP}/api/v1/plugins/${f##*/}"
  done
  rm -f -- "${SNAP}/store.json.sig"
  ssh-keygen -q -Y sign -f "${KEY}" -n omarchy-plugin-check-snapshot "${SNAP}/store.json"
}

# The standard world: two listed remotes, a signed snapshot, dev trust, accepted.
standard_world() {
  make_remote test/safe-clock test.safe-clock
  make_remote test/caution-mail test.caution-mail
  make_snapshot
  trust_as_dev
  "${CLI}" update "file://${SNAP}/store.json" > /dev/null
}

calls() { cat -- "${FAKE_LOG}"; }
