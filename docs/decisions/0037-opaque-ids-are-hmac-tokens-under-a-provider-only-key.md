# 0037. Opaque ids are HMAC tokens under a provider-only key

- Status: accepted
- Date: 2026-10-03
- Supersedes: —

## Context

Published reports must not let anyone map an opaque rule or finding id back to the private rule
it stands for (ADR-0011). Any unkeyed hash of a guessable name is reversible by hashing every
candidate name, so the hash must be keyed with a secret only the provider holds.

## Decision

**A provider's published report extension replaces every rule id, YARA rule name and finding id
with `r.`/`F-` + the first 12 hex of HMAC-SHA256(provider-only key of at least 32 random bytes,
kind NUL id), and refuses to emit a report without that key.**

## Consequences

- Tokens are stable per (key, id), so diffs and links between reviews keep working across rule
  releases; nobody without the key can test a guess. 48 bits keep collisions out of reach for the
  few thousand ids a provider has; the key, not the length, prevents reversal.
- Fail closed: a missing or short key means no report extension at all. The key lives only on the
  provider's machine or CI secret, never in a repository, image or log.
- Rotation changes every token: the next feed reads as "all rules changed" for clients diffing
  tokens and old reports no longer link to new ones, so a provider rotates only on suspected
  exposure and re-publishes all statements in one feed version.
