#!/usr/bin/env bats
# `setup [--uninstall] [--plan] [--json] [--yes]`: links, menu entries and the store keybind,
# planned from one set of facts, idempotent, backed up, never clobbering user content (ADR-0042).

load helpers

setup() {
  setup_env
  MENU="${HOME}/.config/omarchy/extensions/omarchy-menu.jsonc"
  LINK="${HOME}/.local/bin/omarchy-plugin-check"
  STORE_LINK="${HOME}/.local/bin/omarchy-store"
  BINDS="${HOME}/.config/hypr/bindings.lua"
  mkdir -p "${HOME}/.config/omarchy/extensions" "${HOME}/.config/hypr" "${PLUGIN}/store/bin"
  # the store app ships next to the checker in the omarchy-store repository
  printf '#!/bin/sh\nexit 0\n' > "${PLUGIN}/store/bin/omarchy-store"
  chmod +x "${PLUGIN}/store/bin/omarchy-store"
  cat > "${MENU}" << 'JSONC'
{
  // my own entries
  "personal": {"icon":"","label":"Personal"},
  "personal.notes": {"icon":"󰎞","label":"Notes","action":"omarchy-launch-editor ~/notes"}
}
JSONC
  cp "${MENU}" "${BATS_TEST_TMPDIR}/menu.orig"
  printf -- '-- my bindings\no.bind("SUPER + ALT + L", "Learn", "learn")\n' > "${BINDS}"
  cp "${BINDS}" "${BATS_TEST_TMPDIR}/binds.orig"
  # Hyprland's view: SUPER + SHIFT + S is Google Maps (as on a stock Omarchy)
  export FAKE_BINDS="${BATS_TEST_TMPDIR}/binds.json"
  echo '[{"modmask": 65, "key": "S", "submap": "", "description": "Google Maps", "dispatcher": "__lua"},
         {"modmask": 64, "key": "S", "submap": "", "description": "Toggle scratchpad"}]' > "${FAKE_BINDS}"
}

parse_menu() { # the shell's reader: strip whole-line // comments and trailing commas
  jq -R -s -L "${ROOT}/lib" 'include "opc"; strip_jsonc | fromjson' "${MENU}"
}
backups() { find "${HOME}" -name '*.bak.*' | wc -l; }

@test "setup --yes links the CLI and the store, adds the menu entries and a free keybind" {
  run "${CLI}" setup --yes
  [ "${status}" -eq 0 ]
  [ "$(readlink -f "${LINK}")" = "$(readlink -f "${CLI}")" ]
  [ "$(readlink -f "${STORE_LINK}")" = "${PLUGIN}/store/bin/omarchy-store" ]
  parse_menu | jq -e --arg store "${PLUGIN}/store/bin/omarchy-store" '.personal.label == "Personal"
    and ."personal.notes".action == "omarchy-launch-editor ~/notes"
    and (."setup.plugin.check".action | test("^omarchy-launch-floating-terminal-with-presentation .*omarchy-plugin-check check.$"))
    and (."setup.plugin.audit".action | test("omarchy-plugin-check status.$"))
    and ."install.plugin-store".action == $store and ."install.plugin-store".label == "Plugin Store"'
  # SUPER + SHIFT + S is taken, so the next candidate
  grep -qx "o.bind(\"SUPER + SHIFT + ALT + S\", \"omarchy-store\", \"${PLUGIN}/store/bin/omarchy-store\")" "${BINDS}"
  head -2 "${BINDS}" | cmp - "${BATS_TEST_TMPDIR}/binds.orig"
  [[ ${output} == *"SUPER + SHIFT + S is taken (Google Maps)"* ]]
  [ "$(backups)" -eq 2 ]
  [[ ${output} == *"next: omarchy-plugin-check update"* ]]
  run ! grep -q "hyprctl dispatch\|hyprctl keyword\|hyprctl reload" "${FAKE_LOG}"
}

@test "--plan --json lists exactly what would change and writes nothing" {
  run "${CLI}" setup --plan --json
  [ "${status}" -eq 0 ]
  jq -e '.mode == "add" and .pending
    and ([.changes[].what] == ["link", "link", "menu", "keybind"])
    and ([.changes[].action] == ["create", "create", "edit", "edit"])
    and (.changes[2].text | test("Install › Plugin Store, Setup › Plugins › Check Plugin, Setup › Plugins › Audit Plugins"))
    and (.changes[3].text | test("^keybind SUPER \\+ SHIFT \\+ ALT \\+ S → omarchy-store in ~/.config/hypr/bindings.lua"))' <<< "${output}"
  [ ! -e "${LINK}" ] && [ ! -e "${STORE_LINK}" ]
  cmp "${MENU}" "${BATS_TEST_TMPDIR}/menu.orig"
  cmp "${BINDS}" "${BATS_TEST_TMPDIR}/binds.orig"
  [ "$(backups)" -eq 0 ]
}

@test "without --yes and without a terminal nothing changes" {
  run "${CLI}" setup
  [ "${status}" -eq 1 ]
  [[ ${output} == *"pass --yes"* ]]
  [ ! -e "${LINK}" ]
  cmp "${BINDS}" "${BATS_TEST_TMPDIR}/binds.orig"
}

@test "setup is idempotent: a second run changes nothing, keeps the key and makes no new backup" {
  "${CLI}" setup --yes
  cp "${MENU}" "${BATS_TEST_TMPDIR}/menu.after1"
  cp "${BINDS}" "${BATS_TEST_TMPDIR}/binds.after1"
  # our own binding now shows up in Hyprland too; it must not count as a conflict
  echo '[{"modmask": 65, "key": "S", "description": "Google Maps"}, {"modmask": 73, "key": "S", "description": "omarchy-store"}]' > "${FAKE_BINDS}"
  run "${CLI}" setup --yes
  [ "${status}" -eq 0 ]
  [[ ${output} == *"nothing to change"* ]]
  [[ ${output} == *"keybind SUPER + SHIFT + ALT + S → omarchy-store already in"* ]]
  cmp "${MENU}" "${BATS_TEST_TMPDIR}/menu.after1"
  cmp "${BINDS}" "${BATS_TEST_TMPDIR}/binds.after1"
  [ "$(backups)" -eq 2 ]
  run "${CLI}" setup --plan --json
  jq -e '.pending == false and all(.changes[]; .action == "keep")' <<< "${output}"
}

@test "--uninstall --yes undoes links, menu entries and the keybind, nothing else" {
  "${CLI}" setup --yes
  run "${CLI}" setup --uninstall --plan --json
  jq -e '[.changes[].action] == ["remove", "remove", "edit", "remove"]
    and (.changes[3].text | test("SUPER \\+ SHIFT \\+ ALT \\+ S"))' <<< "${output}"
  run "${CLI}" setup --uninstall --yes
  [ "${status}" -eq 0 ]
  [ ! -e "${LINK}" ] && [ ! -e "${STORE_LINK}" ]
  cmp "${BINDS}" "${BATS_TEST_TMPDIR}/binds.orig"
  run diff "${BATS_TEST_TMPDIR}/menu.orig" "${MENU}"
  # only the comma we added after the user's last entry remains
  [[ ${output} == *'>   "personal.notes": {"icon":"󰎞","label":"Notes","action":"omarchy-launch-editor ~/notes"},'* ]]
  parse_menu | jq -e 'keys == ["personal", "personal.notes"]'
  run "${CLI}" setup --uninstall --plan --json
  jq -e '.pending == false' <<< "${output}"
}

@test "--uninstall leaves a link that is not ours alone" {
  mkdir -p "${HOME}/.local/bin"
  ln -s /bin/true "${STORE_LINK}"
  run "${CLI}" setup --uninstall --yes
  [ "${status}" -eq 0 ]
  [ "$(readlink "${STORE_LINK}")" = /bin/true ]
}

@test "without Hyprland the first candidate is used and the plan says conflicts were not checked" {
  unset FAKE_BINDS
  run "${CLI}" setup --yes
  [ "${status}" -eq 0 ]
  [[ ${output} == *"conflicts not checked"* ]]
  grep -q '^o.bind("SUPER + SHIFT + S", "omarchy-store", ' "${BINDS}"
}

@test "every candidate taken: the keybind is skipped, the rest applies" {
  echo '[{"modmask": 65, "key": "S"}, {"modmask": 73, "key": "S"}, {"modmask": 69, "key": "s"}, {"modmask": 76, "key": "S"}]' > "${FAKE_BINDS}"
  run "${CLI}" setup --yes
  [ "${status}" -eq 0 ]
  [[ ${output} == *"every candidate is taken"* ]]
  cmp "${BINDS}" "${BATS_TEST_TMPDIR}/binds.orig"
  [ -L "${STORE_LINK}" ]
}

@test "an older hyprlang bindings.conf gets a bindd line" {
  rm -f "${BINDS}"
  printf 'bind = SUPER, Q, killactive\n' > "${HOME}/.config/hypr/bindings.conf"
  run "${CLI}" setup --yes
  [ "${status}" -eq 0 ]
  grep -qx "bindd = SUPER SHIFT ALT, S, omarchy-store, exec, ${PLUGIN}/store/bin/omarchy-store" "${HOME}/.config/hypr/bindings.conf"
  run "${CLI}" setup --plan --json
  jq -e '.pending == false' <<< "${output}"
  "${CLI}" setup --uninstall --yes
  [ "$(cat "${HOME}/.config/hypr/bindings.conf")" = "bind = SUPER, Q, killactive" ]
}

@test "no bindings file: the keybind is skipped with a hint" {
  rm -f "${BINDS}"
  run "${CLI}" setup --yes
  [ "${status}" -eq 0 ]
  [[ ${output} == *"bind omarchy-store yourself"* ]]
}

@test "without the store app only the CLI link and the checker's menu entries are offered" {
  rm -rf "${PLUGIN}/store"
  run "${CLI}" setup --plan --json
  jq -e '[.changes[] | .what + ":" + .action] == ["link:create", "menu:edit", "keybind:skip"]
    and (.changes[2].text | test("no store app"))' <<< "${output}"
  "${CLI}" setup --yes
  parse_menu | jq -e 'has("install.plugin-store") | not'
}

@test "an existing foreign file at the link path is backed up, not clobbered" {
  mkdir -p "${HOME}/.local/bin"
  echo mine > "${LINK}"
  "${CLI}" setup --yes
  [ -L "${LINK}" ]
  grep -qx mine "${LINK}".bak.*
}

@test "an unparsable menu file is left untouched" {
  printf '{ "a": \n' > "${MENU}"
  cp "${MENU}" "${BATS_TEST_TMPDIR}/broken"
  run "${CLI}" setup --yes
  [ "${status}" -ne 0 ]
  [[ ${output} == *"left"*"untouched"* ]]
  cmp "${MENU}" "${BATS_TEST_TMPDIR}/broken"
  [ ! -e "${LINK}" ]
}

@test "a missing menu file is created with just our block" {
  rm -f "${MENU}"
  "${CLI}" setup --yes
  parse_menu | jq -e 'keys == ["install.plugin-store", "setup.plugin.audit", "setup.plugin.check"]'
}
