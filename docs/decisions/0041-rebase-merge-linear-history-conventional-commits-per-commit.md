# 0041. Rebase-merge onto a linear history; every commit is a Conventional Commit

- Status: accepted
- Date: 2026-10-03
- Supersedes: 0017

## Context

ADR-0017 chose squash merges with the PR title as the only structured message. In practice the
repositories rebase-merge: `master` requires linear history, and a PR often carries several
self-contained commits (code, regenerated data, docs) whose messages are worth keeping apart.

## Decision

**PRs are rebase-merged onto a linear `master`, and every commit that lands (not just the PR title)
follows Conventional Commits (types feat fix docs refactor test chore ci build perf security;
scopes = top-level dirs).**

## Consequences

- Each commit must build, pass `just check` and say what it does; clean up fixups before merging.
- History stays bisectable per commit; no merge or squash commits on `master`.
- Enforced by branch protection (required linear history, required checks `python` and
  `plugin-store`); the message format is a review rule, not a CI check.
