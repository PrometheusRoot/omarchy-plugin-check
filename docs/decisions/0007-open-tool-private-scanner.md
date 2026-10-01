# 0007. Open tool, private scanner

- Status: accepted
- Date: 2026-10-01
- Supersedes: —

## Context

Publishing detection rules and weights lets attackers bulk-test evasions.

## Decision

**Spec, aggregator, site and client plugin are public; stages, rules, prompts, weights and fixtures live in a private scanner repo, with history split before publishing.**

## Consequences

- Public reports expose categories and evidence locations, not internal rule ids or weights.
- The public spec (`schemas/`, provider protocol, Finding vocabulary) is the only contract between repos.
- `git filter-repo` split is a precondition of the first public push.
