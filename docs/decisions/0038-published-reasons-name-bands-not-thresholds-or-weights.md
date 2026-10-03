# 0038. Published reasons name score bands, not thresholds or weights

- Status: accepted
- Date: 2026-10-03
- Supersedes: —

## Context

ADR-0011 keeps the scoring rules private, yet a published report that copies the provider's
verdict reasons verbatim would state the threshold each score crossed. Public docs disclose what
each outcome means and which hard-fail categories exist; the numbers stay private.

## Decision

**A provider's published report extension words `verdict.reasons` without numbers from its
scoring rules: a score line names the band ("score in the risky band"), capabilities are listed
by name in one line, and no other numeric comparison is kept; `verdict.score` is published.**

## Consequences

- Readers see why an outcome was reached (band, severities, capabilities, external code, AI
  escalation) without any number from the scoring rules in a published string.
- Bands can still be estimated from many published (score, outcome) pairs; the score is public
  on purpose (store and site show it), so this removes the stated constants, not the signal.
- Enforced by the provider's tests before a report extension is emitted, and by a leak scan over
  every published file.
