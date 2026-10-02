#!/usr/bin/env bash
# Refresh the store's bundled dev data (store/dev/) from a snapshot build directory
# (scripts/build-snapshot.sh --out DIR): the client bundle's home + search files (gzipped,
# unpacked by the app on first run) and the detail documents of the reviewed plugins only,
# with a store-details.json that lists just those. Shipped with the app, so not verified
# (ADR-0032); the header says "dev".
#   store/tools/dev-bundle.sh SNAPSHOT_DIR
set -euo pipefail
src=${1:?usage: dev-bundle.sh SNAPSHOT_DIR}
dev=$(cd "$(dirname "$0")/../dev" && pwd)
api=$(jq -r '.apiBase' "$src/store-home.json")
reviewed=$(jq -r '.plugins[] | select(.verdict.basis == "trusted") | .id' "$src/store.json")
rm -rf "$dev/api" "$dev"/store-*.json "$dev"/store-*.json.gz
mkdir -p "$dev/${api%/}/plugins"
for f in store-home.json store-search.json; do gzip -9nc "$src/$f" > "$dev/$f.gz"; done
for id in $reviewed; do cp "$src/${api%/}/plugins/$id.json" "$dev/${api%/}/plugins/"; done
jq --argjson keep "$(jq -Rn '[inputs]' <<< "$reviewed")" \
  '.docs |= with_entries(select(.key as $k | $keep | index($k)))' "$src/store-details.json" > "$dev/store-details.json"
echo "dev data from $src: $(wc -w <<< "$reviewed") reviewed plugin(s)"
ls -la "$dev"
