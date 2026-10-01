# 0002. Bind every review to a commit

- Status: accepted
- Date: 2026-10-01
- Supersedes: —

## Context

`omarchy plugin add` clones mutable upstream HEAD and the marketplace does not bind installs to the reviewed commit.

## Decision

**Every report is keyed by (plugin id, git commit, tree); clients compare the installed HEAD/tree, never names or versions.**

## Consequences

- Client states `stale` and `marketplace-mismatch` are computable locally.
- A rescan is needed for every new commit; reports themselves never expire.
- Report path `plugins/<id>/<sha>.json` is immutable.
