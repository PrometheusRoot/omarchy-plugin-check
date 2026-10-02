# Verified store.json -> compact lookup index (cache/index.json). Run only after the
# signature verified; keyed to the snapshot bytes by $sha so a new snapshot rebuilds it.
#   jq -c -L lib --arg sha <sha256> -f lib/index.jq store.json
include "opc";

{
  sha: $sha,
  version, generatedAt, expires, dev, apiBase,
  catalog,
  providers: (.providers | map({key: .id, value: {name, tier, verification, rows}}) | from_entries),
  ids: (.plugins | map({key: .id, value: {
    id, name, author, cat, kind, license, repo, formerRepos, path, install, state, verif, verdict, report
  } | del(.[] | nulls)}) | from_entries),
  # Current repositories first; a former name (ADR-0034) only where no listing owns it now.
  repos: (.plugins as $all
    | (reduce ($all[] | {k: (.repo | repo_key), id} | select(.k)) as $p ({}; .[$p.k] += [$p.id])) as $current
    | reduce ($all[] | .id as $id | (.formerRepos // [])[] | {k: repo_key, id: $id} | select(.k)) as $p
      ($current; if $current[$p.k] then . else .[$p.k] += [$p.id] end))
}
