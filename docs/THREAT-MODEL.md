# Threat model

Public version. The detailed controls of the private scanner and its runner (exact isolation
flags, egress rules, credential handling, reviewer integrity checks) are kept in the private
repository; publishing them would help an attacker more than a user (ADR-0007, ADR-0011).

## Assets

| Asset | Why it matters |
|---|---|
| End user's machine | Plugins run unsandboxed in `omarchy-shell`; RCE = full user-session compromise (SSH keys, GPG, browser sessions, sudo timestamp). |
| Correctness of a published verdict | A wrong `safe` is worse than no tool: users trust it to gate installs. |
| The AI reviewer's integrity | A plugin author controls the text the reviewer reads; a compromised reviewer launders a malicious plugin into `safe`. |
| Signing keys and review infrastructure | The snapshot signing key and the provider's CI identity. Leak → forged verdicts for every client. |
| Provider data repos | Their git history is the audit log; tampering hides a bad review or forges a good one. |

## Adversaries

| Adversary | Goal | Vector |
|---|---|---|
| Malicious plugin author (→ users) | RCE / persistence / credential theft on installers | Process execution from QML, remote scripts piped into a shell, writes to credential stores, autostart persistence, bundled binaries. |
| Malicious plugin author (→ our reviewer) | Make the review say `safe`, or probe the rules | Prompt injection in README/comments/strings, hidden Unicode to disguise code, fake "already audited" claims; repeated submissions to learn the rules. |
| Mutable-HEAD attacker | Get reviewed as benign, then push malware to the same branch | Marketplace binds installs to no commit; upstream HEAD moves after review. |
| Dependency / supply-chain attacker | Land code via a dependency or an unpinned remote fetch | Unpinned `git clone`, typosquatted packages, vulnerable dependencies. |
| Infrastructure attacker | Forge reports or a snapshot | Compromise a provider's CI, a mirror, or the network path to clients. |

## Trust boundaries

```
UNTRUSTED plugin repo  │  reviewed in an isolated, network-less environment; never executed
   ─────────────── boundary: nothing the plugin controls can execute or reach the net ───────────────
provider (private scanner, short-lived machines, no long-lived secrets)
   ─────────────── boundary: unsigned statements → provider CI signs keyless (Sigstore) ───────────────
provider feed (public data repo)  │  in-toto statements, versioned + expiring feed index
   ─────────────── boundary: aggregator verifies every bundle against providers.json ───────────────
aggregator → static snapshot (Pages)  │  signed with the project key (ssh-keygen -Y)
   ─────────────── boundary: clients verify signature, expiry and version before parsing ───────────────
client (CLI / panel / store)  │  local lookups; compares installed HEAD + tree with the signed subject
```

## Mitigations

| Threat | Mitigation |
|---|---|
| Plugin RCE during review | The plugin is never executed; scanners and the AI reviewer run isolated, without network, on single-use machines. |
| Prompt injection → false `safe` | AI is **escalate-only** and cannot reach `blocked` or lower any outcome; scanner hard-fails are non-overridable; injection text is itself reported as a finding; reviewer integrity checks discard all AI input when they fail (ADR-0003). |
| Rule probing (oracle attacks) | No scan on demand (only marketplace-listed plugins), opaque rule ids, undisclosed canary rules, rescan of everything on rule change, delayed negative verdicts for new authors (ADR-0011). |
| Hidden Unicode / trojan source | Invisible and bidirectional control characters in code are hard-fails. |
| Mutable HEAD | Reviews are commit- and tree-bound; clients report `stale` and can pin to the reviewed commit (ADR-0002, ADR-0035). |
| Repo suppressing its own findings | The scanner ignores every in-repo suppression and tool configuration. |
| Forged or replayed verdicts | Statements are Sigstore-signed in the provider's CI with an identity pinned in the signed `providers.json`; feeds and snapshots carry monotonic versions and expiries; clients reject bad signatures, expired files and rollbacks (ADR-0008, ADR-0027, ADR-0028). |
| One lenient provider hiding another's warning | Combined verdict = worst of trusted providers; per-provider rows always shown; `contested` badge (ADR-0009). |
| Data tampering in a mirror | Clients verify the signed snapshot and the sha256 of every listed file before use (ADR-0013, ADR-0032). |
| Privacy of what users install | One snapshot download, all lookups local (ADR-0013). |

## Non-goals (this scope)

Dynamic/behavioural detonation (v2), reviewing the whole 4,523-plugin catalog (P7),
defending a user who edits an installed plugin after review, and defending against a
compromised Anthropic API or GitHub itself.
