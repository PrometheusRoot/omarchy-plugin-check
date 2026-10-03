# Verdict logic (outcome semantics)

What a verdict from our provider (`opc`) means, and the rules every outcome obeys. This is the
public specification of *semantics*. The executable rules (rule identifiers, the hard-fail list,
severity weights, thresholds, scoping and the AI reviewer's internals) live in the private scanner
repository and are deliberately not published (ADR-0007, ADR-0011): a published rule set is a free
evasion-testing kit. How several providers are combined is public: ADR-0009, ADR-0027 and
spec/PROTOCOL.md.

## Outcomes

| outcome | meaning |
|---|---|
| `safe` | No scanner evidence of risky behaviour in the reviewed commit, and the plugin relies on no unreviewed external code. |
| `caution` | The plugin does something that deserves a look before installing: it runs processes, uses the network, writes outside its own directory, installs packages, or relies on code that was not part of the review (external binaries or registry packages). Not evidence of malice. |
| `risky` | Strong scanner evidence of dangerous behaviour (at least one high-severity finding, or a large amount of medium evidence). Install only if you understand and accept it. |
| `blocked` | A scanner found unambiguous malicious or never-acceptable behaviour (a *hard-fail*). The checker refuses to install it; the store hides it from shelves. |

`unknown` (aggregate only) means no trusted provider has reviewed the plugin (ADR-0027).

## Principles

- **Scanners are ground truth.** Only scanner evidence can make a plugin `blocked`, and no AI
  input can override it (ADR-0003).
- **AI is escalate-only.** The AI reviewer may add findings and raise the outcome by **one** level
  (`safe` → `caution` → `risky`). It never lowers an outcome, never reaches `blocked` and never
  un-blocks. AI findings are shown as evidence, marked `source: "ai"`; they never count as
  hard-fails.
- **Distrust on doubt.** If any integrity check of the AI reviewer fails, all AI input for that
  review is discarded and the outcome is the scanners' alone (`ai.guard` in the report says so).
- **Text in the plugin is data.** Prompt-injection text found in a plugin is itself reported as an
  `injection` finding; it never changes how the review is done.
- **Deterministic.** Same commit, same rules → same outcome. Any rule change rescans everything
  (`review.rulesVersion`, ADR-0011).
- **Commit-bound.** A verdict is about one commit and tree; it says nothing about later commits
  (ADR-0002).

## What can hard-fail (non-exhaustive, by category)

Known malware campaign indicators; remote code piped into a shell or decoded payloads executed;
reverse shells; writes into credential stores (SSH, GPG, browser profiles) or sudoers; reading
credentials or private keys; undeclared persistence (shell startup files, Hyprland autostart,
systemd units, cron, XDG autostart, package-manager hooks); invisible or bidirectional Unicode
that disguises code; live verified secrets; opaque bundled binaries that also use the network.
The exact rules, their scope and some undisclosed canary rules are private (ADR-0011).

## Score (0–100)

Each report carries a 0–100 risk score derived from scanner evidence only (severity and
confidence of findings, the plugin's capabilities, minus small credits for good hygiene such as
tests and pinned dependencies). Higher is riskier. The outcome is not a pure function of the score:
evidence of a certain severity sets a floor on its own. AI input never changes the score. The
weights and thresholds are private; the score is shown to help compare plugins, not to be gamed.

## Criteria (`verdict.criteria`)

Provider-protocol vocabulary (spec/PROTOCOL.md), each criterion in exactly one of `checked` /
`notChecked`; `failed` ⊆ `checked`:

| criterion | failed when | not checked when |
|---|---|---|
| `safe-to-run` | outcome `risky` or `blocked` | the plugin relies on unreviewed external code |
| `no-network` / `no-exec` / `no-persistence` / `no-privilege` | that capability is present | — |
| `no-obfuscation` / `no-secrets` | scanner evidence of that category of at least medium severity | — |
| `reviewed-by-human` | — | always (automated review) |

## External code (ADR-0019)

A review covers the repository at one commit. When a plugin runs binaries that are neither shipped
in the repository nor part of the Omarchy base install, or declares runtime registry dependencies,
that code was not reviewed: the outcome is at least `caution`, `verdict.reasons` names the
externals, `capabilities.externalCode.externals[]` lists them, and `safe-to-run` is reported as not
checked.

## Client-side states (not stored in the report)

Computed by the CLI, panel and store against the live install (docs/ARCHITECTURE.md "Checker
plugin"):

| state | condition |
|---|---|
| `unreviewed` | no trusted review exists for this plugin |
| `stale` | installed HEAD/tree ≠ the reviewed commit/tree |
| `unlisted` | not a marketplace plugin, or its origin is not the listed repository |
| `retired` | retired by the marketplace registry |
