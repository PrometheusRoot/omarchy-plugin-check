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
    id, name, author, cat, kind, license, repo, path, install, state, verif, verdict, report
  } | del(.[] | nulls)}) | from_entries),
  repos: (reduce (.plugins[] | {k: (.repo | repo_key), id} | select(.k)) as $p
    ({}; .[$p.k] += [$p.id]))
}
