#!/usr/bin/env bats
# Pure jq library (lib/*.jq): identity, classification, gate, file edits.

load helpers

q() { jq -n -r -L "${ROOT}/lib" "include \"opc\"; $1"; }

@test "repo_key: one key for every spelling of a GitHub repo; null for what it cannot match" {
  [ "$(q '"https://github.com/O/R"|repo_key')" = github.com/o/r ]
  [ "$(q '"https://github.com/O/R.git/"|repo_key')" = github.com/o/r ]
  [ "$(q '"git@github.com:O/R.git"|repo_key')" = github.com/o/r ]
  [ "$(q '"ssh://git@github.com:22/O/R"|repo_key')" = github.com/o/r ]
  [ "$(q '"git+https://github.com/O/R"|repo_key')" = github.com/o/r ]
  local bad
  for bad in file:///tmp/x /tmp/x https://github.com/o https://github.com/o/../r 'ext::sh -c x' https://github.com/a:b/c ""; do
    [ "$(jq -n -r -L "${ROOT}/lib" --arg u "${bad}" 'include "opc"; $u | repo_key')" = null ]
  done
}

@test "classify: blocked and retired win; untrusted is unreviewed; commit or tree match" {
  local row='{"verdict":{"combined":"caution","basis":"trusted","commit":"a"}}'
  local rev='{"commits":["a"],"tree":"t"}'
  [ "$(q "classify(${row}; {head: \"a\", tree: null}; ${rev})")" = caution ]
  [ "$(q "classify(${row}; {head: \"b\", tree: \"t\"}; ${rev})")" = caution ]
  [ "$(q "classify(${row}; {head: \"b\", tree: \"u\"}; ${rev})")" = stale ]
  [ "$(q "classify(${row}; {head: null, tree: null}; ${rev})")" = stale ]
  [ "$(q 'classify({verdict: {combined: "blocked", basis: "trusted"}}; {head: "x"}; {commits: []})')" = blocked ]
  [ "$(q 'classify({state: "retired", verdict: {combined: "safe", basis: "trusted"}}; {}; {commits: []})')" = retired ]
  [ "$(q 'classify({verdict: {combined: "caution", basis: "untrusted"}}; {head: "a"}; {commits: ["a"]})')" = unreviewed ]
  [ "$(q 'classify({verdict: {combined: "unknown", basis: "trusted"}}; {head: "a"}; {commits: ["a"]})')" = unreviewed ]
  [ "$(q 'classify(null; {}; {commits: []})')" = unlisted ]
  [ "$(q 'classify({state: "builtin"}; {}; {commits: []})')" = unlisted ]
}

@test "gate: blocked/retired refuse with 2; safe proceeds; everything else confirms" {
  [ "$(q 'gate("blocked"; {}) | "\(.action) \(.code)"')" = "refuse 2" ]
  [ "$(q 'gate("retired"; {}) | "\(.action) \(.code)"')" = "refuse 2" ]
  [ "$(q 'gate("safe"; {}) | .action')" = proceed ]
  [ "$(q 'gate("safe"; {install: ""}) | "\(.action) \(.code)"')" = "refuse 1" ]
  local s
  for s in caution risky stale unreviewed unlisted; do
    [ "$(q "gate(\"${s}\"; null) | .action")" = confirm ]
  done
}

@test "worst_state orders blocked > risky > retired > stale > unlisted > unreviewed > caution > safe" {
  [ "$(q '["safe","caution","unreviewed","unlisted","stale","retired","risky","blocked"] | worst_state')" = blocked ]
  [ "$(q '["safe","caution","unreviewed","unlisted","stale"] | worst_state')" = stale ]
  [ "$(q '["safe","caution"] | worst_state')" = caution ]
  [ "$(q '[] | worst_state')" = null ]
}

@test "reviewed: signed commit and tree from the snapshot; the unsigned view never supplies a tree" {
  local row='{"id":"p","verdict":{"basis":"trusted","commit":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","tree":"3333333333333333333333333333333333333333"}}'
  local view='{"combined":{"commits":["bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"]},"providers":[
    {"tier":"core","counted":true,"commit":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","tree":"2222222222222222222222222222222222222222"}]}'
  run q "reviewed(${row}; ${view}) | \"\(.commits | join(\",\")) \(.tree) \(.signed)\""
  [ "${output}" = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa 3333333333333333333333333333333333333333 true" ]
  # no signed tree: none, whatever the view says
  run q "reviewed(${row} | del(.verdict.tree); ${view}) | .tree"
  [ "${output}" = null ]
  # no signed commit: the view's commits, display only, no tree
  run q "reviewed(${row} | del(.verdict.commit); ${view}) | \"\(.commits | join(\",\")) \(.tree) \(.signed)\""
  [ "${output}" = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb null false" ]
}

@test "repo_keys / moved_from: former repositories identify the listing (ADR-0034)" {
  local row='{"id":"p","repo":"https://github.com/new/name","formerRepos":["https://github.com/old/name"]}'
  [ "$(q "{origin: \"git@github.com:Old/Name.git\"} | [origin_of(${row}), moved_from(${row})] | join(\" \")")" = "true true" ]
  [ "$(q "{origin: \"https://github.com/new/name\"} | [origin_of(${row}), moved_from(${row})] | join(\" \")")" = "true false" ]
  [ "$(q "{origin: \"https://github.com/evil/name\"} | [origin_of(${row}), moved_from(${row})] | join(\" \")")" = "false false" ]
  [ "$(q "{origin: null} | origin_of(${row})")" = false ]
}

@test "menu.jq: comma added after a last entry without one; markers removed cleanly" {
  local f="${BATS_TEST_TMPDIR}/m.jsonc"
  printf '{\n  "a": {"label": "A"}\n}\n' > "${f}"
  jq -R -s -j -L "${ROOT}/lib" --arg mode add --argjson entries '{"x.y": {"label": "Y"}}' -f "${ROOT}/lib/menu.jq" "${f}" > "${f}.new"
  run cat "${f}.new"
  [[ ${output} == *'"a": {"label": "A"},'* ]]
  [[ ${output} == *'"x.y": {"label":"Y"},'* ]]
  jq -R -s -j -L "${ROOT}/lib" --arg mode remove --argjson entries '{}' -f "${ROOT}/lib/menu.jq" "${f}.new" > "${f}.back"
  run grep -c omarchy-plugin-check "${f}.back"
  [ "${output}" = 0 ]
}

@test "changes.jq: same-day entries stack newest first; no rule and no date appends" {
  local f="${BATS_TEST_TMPDIR}/c.md"
  printf '# Log\n\n---\n\n## 2026-10-02\n\n### First\n' > "${f}"
  run jq -R -s -j --arg date 2026-10-02 --arg entry '### Second' -f "${ROOT}/lib/changes.jq" "${f}"
  [ "${output}" = $'# Log\n\n---\n\n## 2026-10-02\n\n### Second\n\n### First' ] # run drops the final newline
  printf '# Log\n' > "${f}"
  run jq -R -s -j --arg date 2026-10-02 --arg entry '### Only' -f "${ROOT}/lib/changes.jq" "${f}"
  [ "${output}" = $'# Log\n\n## 2026-10-02\n\n### Only' ]
}

@test "index.jq: a former repository resolves to its listing but never shadows a current one" {
  local doc='{"providers":[],"plugins":[
    {"id":"a","repo":"https://github.com/o/a","formerRepos":["https://github.com/o/a-old","https://github.com/o/b"]},
    {"id":"b","repo":"https://github.com/o/b"}]}'
  run jq -c -L "${ROOT}/lib" --arg sha x -f "${ROOT}/lib/index.jq" <<< "${doc}"
  [ "$(jq -c .repos <<< "${output}")" = '{"github.com/o/a":["a"],"github.com/o/b":["b"],"github.com/o/a-old":["a"]}' ]
}
