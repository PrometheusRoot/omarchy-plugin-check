# 0003. Scanners are ground truth; AI is escalate-only

- Status: accepted
- Date: 2026-10-01
- Supersedes: —

## Context

An AI reviewer can be prompt-injected by the code it reads; scanners cannot be talked out of a match.

## Decision

**Hard-fails come only from scanners and are never AI-overridable; the AI may add findings and raise the outcome one level, never lower it and never reach `blocked`.**

## Consequences

- `verdict.decide` implements it; `tests/test_properties.py` pins it (AI never lowers, never blocks, guard trip == no AI).
- AI findings are evidence for humans and for escalation, never for the score or hard-fails.
- See docs/VERDICT-LOGIC.md.
