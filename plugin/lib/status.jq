# Installed plugins x verified index -> status document (cache/status.json, read by the
# panel and the bar widget). Pure.
#   jq -L lib --slurpfile local L.json --slurpfile details D.json --argjson snap S
#      --argjson rel R -f lib/status.jq index.json
# $local[0]: [{dir, id, name, origin, head, tree}] from the plugin checkouts
# $details: per-plugin views available offline (unsigned; only their commits are used, when
#   the snapshot names no single reviewed commit)
# $snap: {ok, error, now, url}
# $rel: {dir: "behind" | "ahead" | "diverged"}: where HEAD stands relative to the reviewed
#   commit (git merge-base, local objects only); a dir missing = the reviewed commit is not
#   in the checkout yet (assumed newer)
include "opc";

. as $ix
| ($local[0] // []) as $installed
| def rows_for_origin($o): ($o | repo_key) as $k | if $k == null then [] else [($ix.repos[$k] // [])[] as $i | $ix.ids[$i]] end;
  # Identity (ADR-0010, ADR-0033, ADR-0034): the id and the origin both point at one listing;
  # an origin that is one of the listing's former repositories is that listing, moved.
  def match($p):
    ($ix.ids[$p.id]) as $byId
    | rows_for_origin($p.origin) as $byOrigin
    | if $byId != null and ($p.origin | repo_key) == ($byId.repo | repo_key) then {row: $byId, note: null}
      elif $byId != null and ($p | moved_from($byId)) then {row: $byId, note: null}
      elif $byId != null and $p.origin == null then {row: $byId, note: "not a git checkout"}
      elif ($byOrigin | length) >= 1 then
        {row: (($byOrigin | map(select(.id == $p.id)) | first) // $byOrigin[0]),
         note: (if $byId == null then "manifest id is not the listed id" else null end)}
      elif $byId != null then {row: null, note: "origin is not the listed repository of \($p.id)"}
      else {row: null, note: null}
      end;
  # Which way `omarchy-plugin-check pin` would move this checkout: to the reviewed commit
  # ("forward": an update; "back": HEAD is past the review, unreviewed), or null.
  def repin($state; $rev; $p; $cm; $tm):
    if ($state | IN("blocked", "retired", "unlisted", "unreviewed")) or ($rev.signed | not) or $cm == true or $tm == true then null
    elif ($rel[$p.dir] // "behind") == "behind" then "forward"
    else "back"
    end;
  [ $installed[] as $p
    | match($p) as $m
    | ($m.row) as $row
    | ([$details[] | select(type == "object" and .id == $row.id)] | first) as $view
    | reviewed($row; $view) as $rev
    | (if $snap.ok then classify($row; $p; $rev) else "unreviewed" end) as $state
    | (if ($rev.commits | length) == 0 or $p.head == null then null else ($rev.commits | index($p.head)) != null end) as $cm
    | (if $rev.tree == null or $p.tree == null then null else $p.tree == $rev.tree end) as $tm
    | ($row != null and ($p | moved_from($row))) as $moved
    | {
        id: $p.id, name: ($row.name // $p.name // $p.id), dir: $p.dir, origin: $p.origin,
        head: $p.head, tree: $p.tree,
        listedId: $row.id, repo: ($row.repo // null), moved: $moved, state: $state,
        combined: ($row.verdict.combined // null), basis: ($row.verdict.basis // "none"),
        contested: ($row.verdict.contested == true),
        providers: ($row.verdict.providers // {}),
        reviewed: {commit: ($rev.commits | first), tree: $rev.tree, signed: $rev.signed},
        commitMatch: $cm,
        treeMatch: $tm,
        repin: (if $snap.ok then repin($state; $rev; $p; $cm; $tm) else null end),
        note: (if ($snap.ok | not) then "no verified snapshot"
               elif $moved then "moved: listed at \($row.repo | ltrimstr("https://")); origin is its former repository"
               else $m.note end),
        url: (if $row.id then ($row.id | marketplace_url) else null end)
      }
  ] | sort_by(-(.state | state_rank), .id) as $plugins
| {
    schemaVersion: 1,
    kind: "omarchy-plugin-check/status",
    generatedAt: ($snap.now | todate),
    snapshot: {
      ok: $snap.ok, error: $snap.error, url: $snap.url,
      version: $ix.version, generatedAt: $ix.generatedAt, expires: $ix.expires, dev: $ix.dev,
      catalog: $ix.catalog.generatedAt,
      providers: [($ix.providers // {}) | to_entries[] | {id: .key, tier: .value.tier, verification: .value.verification}]
    },
    worst: ($plugins | map(.state) | worst_state),
    counts: ($plugins | group_by(.state) | map({key: .[0].state, value: length}) | from_entries),
    plugins: $plugins
  }
