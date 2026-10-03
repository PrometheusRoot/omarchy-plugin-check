#!/usr/bin/env bash
# Verify a store snapshot offline (ADR-0013): SSH signature, expiry, anti-rollback.
# usage: verify-snapshot.sh store.json [store.json.sig] [allowed_signers] [min-version]
# exit 0 = trusted; 1 = rejected (reason on stderr); 2 = usage / missing tool.
set -Eeuo pipefail

store="${1:?usage: verify-snapshot.sh store.json [sig] [allowed_signers] [min-version]}"
sig="${2:-$store.sig}"
allowed="${3:-$(dirname "${BASH_SOURCE[0]}")/keys/allowed_signers}"
min_version="${4:-0}"
namespace="omarchy-plugin-check-snapshot"
principal="omarchy-plugin-check"

command -v ssh-keygen > /dev/null || {
  echo "ssh-keygen not found" >&2
  exit 2
}
command -v jq > /dev/null || {
  echo "jq not found" >&2
  exit 2
}

if ! ssh-keygen -Y verify -f "$allowed" -I "$principal" -n "$namespace" -s "$sig" < "$store" > /dev/null 2>&1; then
  echo "signature: BAD ($store)" >&2
  exit 1
fi

# Only now parse the (authenticated) JSON.
expires="$(jq -r '.expires' "$store")"
version="$(jq -r '.version' "$store")"
dev="$(jq -r '.dev' "$store")"
if [[ "$(date -u +%s)" -ge "$(date -u -d "$expires" +%s)" ]]; then
  echo "expired at $expires" >&2
  exit 1
fi
if ((version < min_version)); then
  echo "rollback: version $version < $min_version" >&2
  exit 1
fi
echo "ok version=$version expires=$expires dev=$dev"
