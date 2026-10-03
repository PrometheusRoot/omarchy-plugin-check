# 0019. Unreviewed external code is reported and caps the verdict

- Status: accepted
- Date: 2026-10-01
- Supersedes: —

Public summary of a private scanner decision (ADR-0007); the detection method lives in the private repository.

## Context

A review covers one repository commit. Plugins that run AUR/pacman binaries or install registry
packages behave according to code nobody reviewed, and a report must say so.

## Decision

**Binaries a plugin runs that are neither in the repository nor part of the Omarchy base install,
and declared runtime registry dependencies, are reported as `external-code` findings and the
`externalCode` capability; any external code makes the outcome at least `caution`, adds a
`verdict.reasons` entry, and reports criterion `safe-to-run` as not checked.**

## Consequences

- Report schema: `capabilities.externalCode {level, evidence, externals[]}`, `verdict.reasons[]`,
  `verdict.criteria {checked, failed, notChecked}`, finding category `external-code` (schemas/CHANGELOG.md).
- External code can only add `caution`; it never hides a hard-fail.
