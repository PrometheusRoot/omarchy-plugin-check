#!/usr/bin/env bats
# `setup [--uninstall]`: CLI link + menu entries, idempotent, never clobbering user content.

load helpers

setup() {
  setup_env
  MENU="${HOME}/.config/omarchy/extensions/omarchy-menu.jsonc"
  LINK="${HOME}/.local/bin/omarchy-plugin-check"
  mkdir -p "${HOME}/.config/omarchy/extensions"
  cat > "${MENU}" << 'JSONC'
{
  // my own entries
  "personal": {"icon":"","label":"Personal"},
  "personal.notes": {"icon":"󰎞","label":"Notes","action":"omarchy-launch-editor ~/notes"}
}
JSONC
  cp "${MENU}" "${BATS_TEST_TMPDIR}/menu.orig"
}

parse_menu() { # the shell's reader: strip whole-line // comments and trailing commas
  jq -R -s -L "${ROOT}/lib" 'include "opc"; strip_jsonc | fromjson' "${MENU}"
}

@test "setup links the CLI and adds both menu entries, keeping the user's" {
  run "${CLI}" setup
  [ "${status}" -eq 0 ]
  [ "$(readlink -f "${LINK}")" = "$(readlink -f "${CLI}")" ]
  parse_menu | jq -e '.personal.label == "Personal" and ."personal.notes".action == "omarchy-launch-editor ~/notes"
    and (."setup.plugin.check".action | test("^omarchy-launch-floating-terminal-with-presentation .*omarchy-plugin-check check.$"))
    and (."setup.plugin.audit".action | test("omarchy-plugin-check status.$"))'
  [ "$(find "${HOME}/.config/omarchy/extensions" -name 'omarchy-menu.jsonc.bak.*' | wc -l)" -eq 1 ]
  [[ ${output} == *"next: omarchy-plugin-check update"* ]]
}

@test "setup is idempotent: second run changes nothing and makes no new backup" {
  "${CLI}" setup
  cp "${MENU}" "${BATS_TEST_TMPDIR}/menu.after1"
  run "${CLI}" setup
  [ "${status}" -eq 0 ]
  [[ ${output} == *"already links here"* && ${output} == *"menu: already set up"* ]]
  cmp "${MENU}" "${BATS_TEST_TMPDIR}/menu.after1"
  [ "$(find "${HOME}/.config/omarchy/extensions" -name 'omarchy-menu.jsonc.bak.*' | wc -l)" -eq 1 ]
}

@test "--uninstall removes our link and block only" {
  "${CLI}" setup
  run "${CLI}" setup --uninstall
  [ "${status}" -eq 0 ]
  [ ! -e "${LINK}" ]
  run diff "${BATS_TEST_TMPDIR}/menu.orig" "${MENU}"
  # only the comma we added after the user's last entry remains
  [[ ${output} == *'>   "personal.notes": {"icon":"󰎞","label":"Notes","action":"omarchy-launch-editor ~/notes"},'* ]]
  parse_menu | jq -e 'keys == ["personal", "personal.notes"]'
}

@test "an existing foreign file at the link path is backed up, not clobbered" {
  mkdir -p "${HOME}/.local/bin"
  echo mine > "${LINK}"
  "${CLI}" setup
  [ -L "${LINK}" ]
  grep -qx mine "${LINK}".bak.*
}

@test "an unparsable menu file is left untouched" {
  printf '{ "a": \n' > "${MENU}"
  cp "${MENU}" "${BATS_TEST_TMPDIR}/broken"
  run "${CLI}" setup
  [ "${status}" -ne 0 ]
  [[ ${output} == *"left"*"untouched"* ]]
  cmp "${MENU}" "${BATS_TEST_TMPDIR}/broken"
}

@test "a missing menu file is created with just our block" {
  rm -f "${MENU}"
  "${CLI}" setup
  parse_menu | jq -e 'keys == ["setup.plugin.audit", "setup.plugin.check"]'
}
