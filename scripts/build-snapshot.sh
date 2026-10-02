#!/usr/bin/env bash
# Collector + aggregator end to end (ADR-0026, docs/RUNBOOK.md "Snapshot"):
#   sync → github (resumable) → stats → aggregate api → rank → aggregate + sign store.json and the
#   store client bundle (store-manifest.json + home/search/details, ADR-0032) → verify both.
# usage: build-snapshot.sh --out DIR --providers providers.json [--providers-sig F] [--key KEY]
#        [--seed-catalog old-catalog.json]... [--no-github] [--max-repos N] [--offline-sigstore]
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$root/.venv/bin:$root/.tools/bin:$PATH"
cache="${OPC_CACHE:-$HOME/.cache/omarchy-plugin-check/collector}"
out="" providers="" providers_sig="" key="$HOME/.config/omarchy-plugin-check/dev-snapshot-key"
github=1 max_repos="" offline=""
seeds=()
while (($#)); do
  case "$1" in
    --out) out="$2" && shift ;;
    --providers) providers="$2" && shift ;;
    --providers-sig) providers_sig="$2" && shift ;;
    --key) key="$2" && shift ;;
    --seed-catalog) seeds+=(--seed-catalog "$2") && shift ;;
    --no-github) github=0 ;;
    --max-repos) max_repos="$2" && shift ;;
    --offline-sigstore) offline="--offline" ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
  shift
done
[[ -n "$out" && -n "$providers" ]] || {
  echo "usage: build-snapshot.sh --out DIR --providers providers.json [...]" >&2
  exit 2
}
mkdir -p "$out"
sig_args=()
[[ -n "$providers_sig" ]] && sig_args=(--providers-sig "$providers_sig" --allowed-signers "$root/spec/keys/allowed_signers.dev")
state=(--state "$out/aggregator-state.json")
market=(--catalog "$cache/marketplace/catalog.json" --registry "$cache/marketplace/registry.json")

opc-collect --cache "$cache" sync
if ((github)); then
  rc=0
  opc-collect --cache "$cache" github "${seeds[@]}" ${max_repos:+--max-repos "$max_repos"} || rc=$?
  ((rc == 0 || rc == 3)) || exit "$rc" # 3 = stopped early (rate limit); rerun resumes
fi
opc-collect --cache "$cache" stats --out "$out/stats.json"
opc-aggregate build --providers "$providers" "${sig_args[@]}" "${market[@]}" --out "$out" "${state[@]}" $offline
opc-collect --cache "$cache" rank --stats "$out/stats.json" --api-index "$out/api/v1/index.json" --out "$out/ranking.json"
opc-aggregate build --providers "$providers" "${sig_args[@]}" "${market[@]}" --out "$out" "${state[@]}" $offline \
  --stats "$out/stats.json" --ranking "$out/ranking.json" --sign-key "$key"
"$root/spec/verify-snapshot.sh" "$out/store.json" "$out/store.json.sig" "$root/spec/keys/allowed_signers.dev"
# The store app's client bundle (ADR-0032): the same check the app runs before parsing it.
OPC_STORE_ALLOWED_SIGNERS="$root/spec/keys/allowed_signers.dev" OPC_STORE_VERIFY_STATE="$out/store-bundle-version" \
  "$root/store/bin/omarchy-plugin-store-verify" bundle "$out"
