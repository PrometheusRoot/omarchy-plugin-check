# 0034. store.json carries the reviewed tree and former repositories; a moved checkout keeps its listing

- Status: accepted
- Date: 2026-10-02
- Supersedes: part of 0033 (tree taken from the per-plugin view; renamed repositories unlisted)

## Context

ADR-0033 left two gaps in the signed snapshot. The tree that lets a client accept a re-signed or
rebased commit with identical content lived only in the per-plugin views, which a bare
`store.json` does not sign, so `status` loaded and trusted detail files to get it. And a plugin
whose repository was renamed (the registry lists ~50 `repositoryMigrations` and
`repositoryIdentity.previousRepositories`) showed as `unlisted` for everyone who installed it
under its old name, although GitHub still redirects that name to the same repository.

## Decision

**Each store.json row carries `verdict.tree` (the statements' `subject.digest.gitTree` for the
single trusted commit in `verdict.commit`, only when every trusted row of that commit names the
same tree; also `combined.tree` in `api/v1/plugins/<id>.json`) and `formerRepos` (the listing's
previous repository URLs, leaving out any name that is another listing's current repository);
clients take the tree from the signed row only, and match an installed checkout whose `origin`
is one of `formerRepos` to that listing, flagged `moved`, while the plugin id still has to be the
listed id or the origin has to resolve to the listing.**

## Consequences

- One pure helper (`merge.decided_tree`) feeds both documents; `Marketplace.former` in `opc_spec`
  derives the former names (tests in `aggregator/tests`, `spec/tests`).
- The CLI's `status`, `--add --pin` and `pin` compare `HEAD^{tree}` with `verdict.tree` from the
  signed snapshot; detail documents are display-only for trees. A commit match never depends on it.
- A fork that reuses a listed id under an unrelated repository stays `unlisted`; only the
  marketplace's own migration records widen a listing's identity (ADR-0010).
- A former name can be re-registered by someone else after a rename. A checkout from it gets the
  listing's verdict only for the reviewed commit or tree (anything else is `stale`), and `pin`
  fetches from the listing's current repository, never from the old origin.
- `formerRepos` are lower-cased `https://github.com/owner/name` URLs (the registry's join keys).
