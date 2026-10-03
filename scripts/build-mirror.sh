#!/usr/bin/env bash
# Build the omarchy-store repository tree (ADR-0042): the checker plugin at the root (manifest,
# Panel.qml, BarWidget.qml, bin/, lib/, keys/) and the store app in store/ (shell.qml, ui/, lib/,
# bin/), from one commit of this repository. Tests, dev data and dev tools stay here. The tree
# is validated like `omarchy plugin add` validates it before anything is written elsewhere.
#
#   scripts/build-mirror.sh [--ref REF] OUT               write the tree into OUT (must not exist)
#   scripts/build-mirror.sh [--ref REF] --commit CLONE    replace CLONE's worktree with the tree
#                                                         and commit it on top of CLONE's HEAD
#
# Reproducible: files come from `git archive REF` (default HEAD), so the same REF gives the same
# git tree; with --commit the author/committer date is REF's commit date.
set -Eeuo pipefail

# omarchy-plugin-validate from Omarchy v4.0.4 (MIT), used when Omarchy is not installed (CI).
validate_url="https://raw.githubusercontent.com/basecamp/omarchy/c668141e9c42b13c80c9ca4ea108e11708c5e8a5/bin/omarchy-plugin-validate"
validate_sha256="f7507e5042eb970e3dc918bdf6bf251c7557443892a77e71a17d7019ddde72c8"

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
ref=HEAD
commit=""
out=""
while (($#)); do
  case $1 in
    --ref)
      ref=$2
      shift 2
      ;;
    --commit)
      commit=$2
      shift 2
      ;;
    -*)
      echo "build-mirror: unknown option $1" >&2
      exit 2
      ;;
    *)
      out=$1
      shift
      ;;
  esac
done
[[ -n ${out} || -n ${commit} ]] || {
  echo "usage: scripts/build-mirror.sh [--ref REF] OUT | --commit CLONE" >&2
  exit 2
}

tmp=$(mktemp -d)
trap 'rm -rf -- "${tmp}"' EXIT
src="${tmp}/src"
tree="${tmp}/tree"
mkdir -p -- "${src}" "${tree}/store"
git -C "${root}" archive --format=tar "${ref}" LICENSE plugin store | tar -x -C "${src}"

# Plugin at the root: what the shell loads, the CLI and its filters, the trusted key.
cp -- "${src}/LICENSE" "${src}/plugin/manifest.json" "${src}/plugin/Panel.qml" "${src}/plugin/BarWidget.qml" \
  "${src}/plugin/README.md" "${tree}/"
cp -r -- "${src}/plugin/bin" "${src}/plugin/lib" "${src}/plugin/keys" "${tree}/"
# The store app in store/.
cp -- "${src}/store/shell.qml" "${src}/store/README.md" "${src}/store/SNAPSHOT-FIELDS.md" "${tree}/store/"
cp -r -- "${src}/store/bin" "${src}/store/lib" "${src}/store/ui" "${tree}/store/"
# Tests are not shipped.
find "${tree}" -name '*.test.mjs' -delete

# Checks: no symlinks (Omarchy refuses them), the store finds the checker and the key where
# it looks for them, the launcher is executable, Omarchy's own validation passes.
if [[ -n $(find "${tree}" -type l -print -quit) ]]; then
  echo "build-mirror: symlinks in the tree" >&2
  exit 1
fi
for f in bin/omarchy-plugin-check store/bin/omarchy-store store/bin/omarchy-plugin-store-verify; do
  [[ -x ${tree}/${f} ]] || {
    echo "build-mirror: ${f} is not executable" >&2
    exit 1
  }
done
grep -q '^omarchy-plugin-check namespaces="omarchy-plugin-check-snapshot"' "${tree}/keys/allowed_signers" || {
  echo "build-mirror: keys/allowed_signers holds no production snapshot key" >&2
  exit 1
}
validate=$(command -v omarchy-plugin-validate || true)
if [[ -z ${validate} ]]; then
  validate="${tmp}/omarchy-plugin-validate"
  curl --proto '=https' --tlsv1.2 -fsSL --max-time 60 -o "${validate}" -- "${validate_url}"
  [[ $(sha256sum < "${validate}") == "${validate_sha256}  -" ]] || {
    echo "build-mirror: omarchy-plugin-validate does not match its pinned sha256" >&2
    exit 1
  }
  chmod +x "${validate}"
fi
"${validate}" "${tree}"

version=$(jq -r .version "${tree}/manifest.json")
if [[ -n ${out} ]]; then
  [[ ! -e ${out} ]] || {
    echo "build-mirror: ${out} exists" >&2
    exit 1
  }
  mkdir -p -- "$(dirname -- "${out}")"
  cp -r -- "${tree}" "${out}"
  echo "omarchy-store ${version}: tree in ${out}"
fi
if [[ -n ${commit} ]]; then
  [[ -d ${commit}/.git ]] || {
    echo "build-mirror: ${commit} is not a git clone" >&2
    exit 1
  }
  git -C "${commit}" rm -rq --ignore-unmatch -- .
  cp -r -- "${tree}/." "${commit}/"
  git -C "${commit}" add -A
  sha=$(git -C "${root}" rev-parse "${ref}^{commit}")
  date=$(git -C "${root}" show -s --format=%cI "${sha}")
  if git -C "${commit}" diff --cached --quiet; then
    echo "omarchy-store ${version}: ${commit} already holds this tree"
  else
    GIT_AUTHOR_DATE=${date} GIT_COMMITTER_DATE=${date} git -C "${commit}" commit -q \
      -m "release: omarchy-store ${version}" -m "Built by scripts/build-mirror.sh from PrometheusRoot/omarchy-plugin-check@${sha}."
    echo "omarchy-store ${version}: committed $(git -C "${commit}" rev-parse --short HEAD) (tree $(git -C "${commit}" rev-parse --short 'HEAD^{tree}'))"
  fi
fi
