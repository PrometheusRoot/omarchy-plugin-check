# One command vocabulary for humans, agents and CI (ADR-0015). `just --list` for help.
# Tools come from the repo .venv (Python dev group in pyproject.toml) and .tools/bin (pinned binaries).

set shell := ["bash", "-Eeuo", "pipefail", "-c"]
set positional-arguments

root := justfile_directory()
venv := root / ".venv"
export PATH := venv / "bin" + ":" + root / ".tools/bin" + ":" + env("PATH")

# Python packages (ADR-0026): spec is the bottom; aggregator and collector never import each other.
public := "spec aggregator collector"

# Everything CI gates on.
default: check

# lint + types + tests + architecture + docs freshness
check: lint type test arch docs

# Create .venv with the public packages + the pinned dev group, and install pinned dev binaries into .tools/
setup:
    test -x {{venv}}/bin/python || python3 -m venv {{venv}}
    {{venv}}/bin/pip install -q -U 'pip>=25.1'
    {{venv}}/bin/pip install -q --group pyproject.toml:dev
    for p in {{public}}; do {{venv}}/bin/pip install -q -e "$p"; done
    scripts/install-dev-tools.sh

# Fast checks (same hooks as the git pre-commit hook)
lint:
    prek run --all-files

# Format Python and shell in place
fmt:
    for p in {{public}}; do (cd "$p" && ruff format . && ruff check --fix .); done
    ruff format scripts && ruff check --fix scripts
    shfmt -w -i 2 -ci -bn -sr scripts/*.sh spec/*.sh store/tools/*.sh store/bin/* store/tests/*.bats store/tests/bin/*
    shfmt -w -i 2 -ci -bn -sr plugin/bin/* plugin/tools/*.sh plugin/tests/*.bats plugin/tests/*.bash plugin/tests/bin/*

# basedpyright strict, no baseline (every public package)
type:
    for p in {{public}}; do (cd "$p" && basedpyright); done

# Tests with each package's coverage floor (pyproject: fail_under)
test:
    for p in {{public}}; do (cd "$p" && python -m pytest); done

# Import contracts (public packages never import the private scanner) + dependency hygiene
arch:
    for p in {{public}}; do (cd "$p" && lint-imports && deptry .); done

# Regenerate generated doc sections (ADR index, contract and tool tables); fail if anything changed
docs:
    python3 scripts/check_docs.py

# Install / refresh pinned developer binaries (.tools/bin)
tools:
    scripts/install-dev-tools.sh

# Collector + aggregator end to end → OUT/api/v1 + OUT/store.json(.sig). See docs/RUNBOOK.md.
snapshot *args:
    scripts/build-snapshot.sh "$@"

# Store app (store/): node tests incl. the search latency benchmark over the dev search columns + launcher bats
store-test:
    node --test 'store/lib/*.test.mjs'
    bats store/tests

# Store app: qmllint + qmlformat check + qmldir freshness (`store/tools/qmllint.sh --fix` formats)
store-lint:
    store/tools/qmllint.sh

# Run the store app floating at 1280x800; `just store-run --dev` = fake installer, sample installed list, `t` themes
store-run *args:
    for f in store-home store-search; do test -f store/dev/$f.json || gunzip -k store/dev/$f.json.gz; done
    store/bin/omarchy-store "$@"

# Build the omarchy-store repository tree (plugin at the root, store in store/) into OUT and validate it (ADR-0042)
mirror out *args:
    scripts/build-mirror.sh "$@"

# Refresh the store's bundled dev data from a snapshot build dir (`just snapshot --out DIR`)
store-dev-bundle dir:
    store/tools/dev-bundle.sh "{{dir}}"

# Checker plugin (plugin/): bats CLI tests (temp HOME, fake omarchy + git ls-remote, per-test signing key) + node tests of the panel logic
plugin-test:
    bats plugin/tests
    node --test 'plugin/lib/*.test.mjs'

# Checker plugin: shellcheck (enable=all) + shfmt + qmllint + qmlformat + omarchy plugin validate (`plugin/tools/lint.sh --fix` formats)
plugin-lint:
    plugin/tools/lint.sh

# Site (site/, ADR-0036): astro dev over OPC_API_DIR (default: ../.snapshot from `just snapshot --out .snapshot`); `npm ci` first time
site-dev *args:
    cd site && npx astro dev "$@"

# Site: static build into site/dist (OPC_API_DIR, OPC_SNAPSHOT_DIR, OPC_REGISTRY, OPC_SITE_BASE); prints the time
site-build:
    cd site && SECONDS=0 && npx astro build && echo "site built in ${SECONDS}s, $(du -sh dist | cut -f1)"

# Site: vitest + 4 Playwright e2e over the fixture (PLAYWRIGHT_CHROMIUM=/usr/bin/chromium to use a system browser)
site-test:
    cd site && npx vitest run
    # why: prefer the system Chromium when Playwright's own browser isn't installed (CI installs it)
    cd site && PLAYWRIGHT_CHROMIUM="${PLAYWRIGHT_CHROMIUM:-$(command -v chromium || true)}" npx playwright test

# Site: biome + astro check (strictest tsconfig); `cd site && npx biome check --write .` formats
site-lint:
    cd site && npx biome ci .
    cd site && npx astro check
