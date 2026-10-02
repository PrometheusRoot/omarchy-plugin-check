# One plugin's verdict model for the card and the --add gate. Pure: every input is an arg.
#   jq -n -L lib --argjson row R --arg q Q --argjson local L --argjson upstream U
#      --slurpfile detail FILE --argjson snap S --argjson pin true|false -f lib/model.jq
# $row: index row or null · $local: {installed, head, tree, dir, origin}
# $upstream: {head, error} from `git ls-remote`
# $detail: [unsigned per-plugin view] or [] (slurped: it can exceed one argv string)
# $snap: {version, generatedAt, catalog, dev, providers, now}
include "opc";

# The per-plugin view is unsigned: use it only if it describes this row.
($detail | first // null | if type == "object" and .id == $row.id then . else null end) as $view
| reviewed($row; $view) as $rev
| ($rev.commits | first) as $reviewed
# What would run: the installed checkout, else what --add would clone (the reviewed commit
# when pinning, else upstream HEAD; unknown upstream = assume the reviewed commit, flagged).
| (if $local.installed then {head: $local.head, tree: $local.tree}
   elif $pin and $reviewed != null then {head: $reviewed, tree: $rev.tree}
   elif $upstream.head != null then {head: $upstream.head, tree: null}
   else {head: $reviewed, tree: null}
   end) as $target
| classify($row; $target; $rev) as $state
| gate($state; $row) as $g0
| ($local.installed | not) and ($pin | not) and $upstream.head == null and $reviewed != null as $upUnknown
| ($snap.providers // {}) as $pmeta
| [($view.providers // [])[]
   | select(.counted == true and (.tier == "core" or .tier == "verified"))
   | select(.commit as $c | $rev.commits | index($c))] as $trusted
| {
    q: $q,
    id: $row.id,
    name: ($row.name // $row.id),
    row: $row,
    state: $state,
    combined: ($row.verdict.combined // null),
    basis: ($row.verdict.basis // "none"),
    contested: ($row.verdict.contested == true),
    gate: (if $g0.action == "proceed" and $upUnknown then {action: "confirm", code: 0, reason: "upstream HEAD unknown"} else $g0 end),
    reviewed: {commit: $reviewed, commits: $rev.commits, tree: $rev.tree, signed: $rev.signed},
    upstream: {head: $upstream.head, error: $upstream.error, eq: ($upstream.head != null and $reviewed != null and $upstream.head == $reviewed)},
    local: (if $local.installed then {
      head: $local.head, tree: $local.tree, dir: $local.dir, origin: $local.origin, moved: ($local.moved == true),
      commitEq: ($local.head != null and ($rev.commits | index($local.head)) != null),
      treeEq: (if $rev.tree == null or $local.tree == null then null else $local.tree == $rev.tree end)
    } else null end),
    providers: [($row.verdict.providers // {}) | to_entries[] | {
      id: .key, verdict: .value,
      tier: ($pmeta[.key].tier // "unknown"), verification: ($pmeta[.key].verification // "unknown"),
      capped: (($pmeta[.key].tier // "") | IN("community", "unsigned"))
    }] | sort_by(.tier | IN("core", "verified") | not),
    counted: ([($row.verdict.providers // {}) | keys[] | select(($pmeta[.].tier // "") | IN("core", "verified"))] | length),
    criteria: ($row.verdict.criteria // ($trusted | first | .criteria) // null),
    risk: ($row.verdict.risk // null),
    timeReviewed: ($trusted | map(.timeReviewed) | max),
    summary: ($trusted | first | .summary // null),
    findings: {
      counts: ([$trusted[].findings[]?.severity] | group_by(.) | map({key: .[0], value: length}) | from_entries),
      blocking: [$trusted[].findings[]? | select(.blocking == true) | {
        category, message,
        at: ((.locations // [])[0] | if . == null then null else "\(.path):\(.startLine // "?")" end)
      }]
    },
    viewAvailable: ($view != null),
    mkt: ([$row.cat, $row.kind, $row.license, $row.verif] | map(select(. != null and . != ""))),
    url: (if $row.id then ($row.id | marketplace_url) else null end),
    snapshot: {
      version: $snap.version, dev: $snap.dev,
      age: (if $snap.generatedAt then ($snap.now - ($snap.generatedAt | iso_to_epoch)) else null end),
      catalog: ($snap.catalog.generatedAt // null)
    }
  }
