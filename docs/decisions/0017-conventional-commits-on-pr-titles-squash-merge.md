# 0017. Conventional Commits on PR titles, squash merge

- Status: accepted
- Date: 2026-10-01
- Supersedes: —

## Context

Linear history and changelogs need structured messages without taxing every local commit.

## Decision

**PR titles follow Conventional Commits (types feat fix docs refactor test chore ci build perf security; scopes = top-level dirs) and PRs are squash-merged.**

## Consequences

- Enforced on PR titles in CI, not on local commits.
- The squash commit message is the PR title.
