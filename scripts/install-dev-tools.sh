#!/usr/bin/env bash
# Install pinned developer binaries (standards/dev-tools.lock) into PREFIX/bin.
#   scripts/install-dev-tools.sh [PREFIX]     # default: .tools
# Every download is sha256-verified; nothing is executed before verification.
set -Eeuo pipefail
trap 'echo "install-dev-tools: failed at line $LINENO" >&2' ERR

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
prefix="${1:-$root/.tools}"
mkdir -p "$prefix/bin" "$prefix/.dl"
prefix="$(cd "$prefix" && pwd)"

while read -r name version url sha; do
  [[ -z ${name:-} || $name == \#* ]] && continue
  if [[ -x $prefix/bin/$name ]] && [[ -f $prefix/bin/.$name.version ]] \
    && [[ $(< "$prefix/bin/.$name.version") == "$version" ]]; then
    continue
  fi
  file="$prefix/.dl/$(basename "$url")"
  if [[ ! -f $file ]] || ! echo "$sha  $file" | sha256sum -c --quiet - 2> /dev/null; then
    curl -fsSL --retry 3 -o "$file.part" "$url"
    mv "$file.part" "$file"
  fi
  echo "$sha  $file" | sha256sum -c --quiet - || {
    echo "checksum mismatch: $name" >&2
    exit 1
  }
  tmp="$(mktemp -d)"
  case "$file" in
    *.tar.gz) tar -xzf "$file" -C "$tmp" ;;
    *.zip) python3 -m zipfile -e "$file" "$tmp" ;;
    *) cp "$file" "$tmp/$name" ;;
  esac
  bin="$(find "$tmp" -type f -name "$name" | head -n1)"
  install -m 0755 "$bin" "$prefix/bin/$name"
  echo "$version" > "$prefix/bin/.$name.version"
  rm -rf "$tmp"
  echo "installed $name $version"
done < "$root/standards/dev-tools.lock"
