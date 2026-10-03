# Report dimensions

Every field of `report.schema.json` (v1), the provider's optional `predicate.report` extension
(spec/PROTOCOL.md), why it matters, and the tool that fills it. "Ground truth" fields come from
scanners; the AI never writes them.

**Published reports** (`predicate.report`) carry no raw rule id or finding id anywhere: `findings[].ruleId`, `diffSinceLastReview.resolvedRuleIds`,
hotspot reasons, `verdict.summary`/`reasons`/`aiEscalation`, AI notes and every other string are
rewritten to `r.<12 hex>` / `F-<12 hex>` HMAC tokens under a provider-only key (ADR-0037). Tokens are
stable per key across reviews and rule releases; without the key a report is not emitted.
`verdict.reasons` there names the score band ("score in the risky band") and the capabilities in
one line instead of thresholds or weights; `verdict.score` itself is kept (ADR-0038).

## plugin

| Field | Why | Source |
|---|---|---|
| `id`, `name`, `repo` | Identity; clients key on `id`, compare `repo` remote. | manifest, git |
| `marketplace.verificationCommit` | Detects marketplace-vs-review mismatch (mutable HEAD). | plugins.omarchy.org catalog |
| `marketplace.baselineOutcome`, `caps` | What the shallow marketplace scan claimed; contrast with ours. | catalog |
| `marketplace.stars` | Reach / blast radius; prioritization. | catalog / gh |
| `listingState` | listed / retired (registry retiredPluginIds) / unlisted (not a marketplace plugin). | catalog + registry |
| `marketplace.{listingValidatedCommit, upstreamObservedCommit, catalogGeneratedAt, manifestPath, repositoryLayout, author, description, category, kind, tags, license, installCommand, verificationStatus}` | Marketplace metadata, copied verbatim (the marketplace is the source of truth; we never invent ids/metadata). | catalog |

## review

| Field | Why | Source |
|---|---|---|
| `commit` | The review is bound to this SHA and nothing else. | git |
| `scanTarget` | Which commit: marketplace-verified / marketplace-listing / upstream-observed / upstream-head / explicit / local. | pipeline |
| `pluginPath` | Monorepo/suite subdirectory reviewed (catalog `manifestPath`), "" = root. | catalog |
| `reviewedAt` | Freshness. | orchestrator |
| `scannerVersion`, `rulesVersion` | Reproducibility; a rule change can change a verdict. | pipeline |
| `tools[]` (name/version/status) | Which scanners actually ran; a `skipped`/`failed` tool weakens coverage. | pipeline |
| `aiModel` | Attribution; `null` = `--no-ai`. | pipeline |
| `upstreamHeadAtScan` | Client `stale` detection input. | git ls-remote |
| `previousCommit` | Anchors `diffSinceLastReview`. | data repo |

## verdict (see VERDICT-LOGIC.md for outcome semantics)

| Field | Why | Source |
|---|---|---|
| `outcome` | The headline: safe/caution/risky/blocked. | scanner |
| `score` 0..100 | Relative risk from scanner evidence (higher = riskier); weights are private. | scanner |
| `hardFails[]` | Which findings force `blocked` (opaque ids). | scanner |
| `aiEscalation` | Transparency: what the AI changed and why (`null` if nothing). | scanner |
| `summary` <=200 | One-line human explanation. | scanner |
| `reasons[]` | Every condition behind the outcome, incl. external code relied on (published: bands, not thresholds, ADR-0038). | scanner |
| `criteria` {checked, failed, notChecked} | Provider-protocol criteria; `notChecked` = what this review cannot vouch for. | scanner |

## whatItDoes

| Field | Why | Source |
|---|---|---|
| `oneLiner` | Plain-language purpose for the card. | AI pass 1 |
| `kinds`, `entryPoints` | What the shell will load. | manifest |
| `manifestValid`, `manifestError` | Would the shell even accept it. | manifest validation |

## capabilities (each: level none/low/med/high + evidence[findingId])

Capabilities shape the outcome (see VERDICT-LOGIC.md "Outcomes"); the evidence links each level to findings.

| Capability | Security meaning | Source |
|---|---|---|
| `processExec` | Spawns processes -- the primary RCE surface. | opengrep (QML Process/execDetached), bandit |
| `network` | Reaches the network; exfil / remote payloads. | opengrep (XHR/fetch/curl), host extraction |
| `fileWrite` | Writes outside its own dir -- config/persistence tampering. | opengrep (FileView/writes) |
| `persistence` | Survives restart (shell rc, exec-once, systemd). | opengrep |
| `privilege` | sudo/pkexec/polkit -- escalation. | opengrep |
| `packageInstall` | pacman/AUR/pip/npm -- pulls arbitrary code. | opengrep |
| `bundledBinary` | Ships opaque binaries. | inventory, clamscan |
| `clipboard` | Reads/writes clipboard -- silent data capture. | opengrep |
| `screenCapture` | Screen grab. | opengrep |
| `hyprlandIpc` | Controls the compositor. | opengrep |
| `externalCode` | Runs/installs code not in the reviewed commit (AUR/pacman binaries, registry deps); adds `externals[]` {name, kind, source, evidence}. Forces ≥ caution, `safe-to-run` not checked (ADR-0019). | built-in analysis |

## systemAreas (touched[] + evidence)

Which sensitive OS areas the code reaches. Matters because these are the areas an
attacker abuses; each area links to the findings proving contact.
Enum: `omarchy-shell, hyprland, systemd, pacman-aur, sudoers, shell-rc, ssh, browsers, gpg, dbus`. Source: opengrep path rules.

## network.hosts[]

Every host + scheme + evidence. Matters: reveals where data goes and what code is
fetched; reserved/typosquat hosts are red flags. Source: opengrep + URL extraction.

## dependencies

| Field | Why | Source |
|---|---|---|
| `packages[]` (ecosystem, direct, pinned) | Supply-chain surface; unpinned = mutable. | osv-scanner, guarddog, lockfiles |
| `systemPackages[]` | pacman/AUR the plugin tells users to install. | opengrep, README parse |
| `vulnerabilities[]` | Known CVEs in deps. | osv-scanner |

## secrets

Count + items (findingId, kind, live). **Never** the secret value. Matters: leaked
credentials in the repo; `live` verification distinguishes a real leak. Source: gitleaks.

## supplyChain

| Field | Why | Source |
|---|---|---|
| `scorecard` (`null` if unavailable) | OpenSSF hygiene signal. | OpenSSF Scorecard |
| `pinnedDeps` (`null` = no deps) | Mutable-dep risk. | lockfile analysis |
| `signedCommitRatio` | Provenance. | gh API |
| `busFactor` | Maintenance / takeover risk. | git shortlog |
| `repoAgeDays` | Young repos are higher-risk. | git |
| `unpinnedRemoteFetches[]` | Fetches that pull mutable remote code. | opengrep |

## injection (hiddenUnicode, promptInjection, obfuscation -- each count + evidence)

Directly the anti-reviewer threat: hidden Unicode/bidi (trojan source), prompt-injection
strings targeting an AI reviewer, and obfuscation.
Source: heckler (unicode), ctxsentry (prompt injection), opengrep (obfuscation).

## codeQuality

| Field | Why | Source |
|---|---|---|
| `loc` (total, byLanguage) | Size / audit effort. | cloc/tokei |
| `lint[]` (errors/warnings) | Baseline hygiene. | shellcheck, eslint, qmllint, bandit |
| `tests` (present, files) | Signals maturity. | inventory |
| `docs` (readme, changelog) | Trust / transparency. | inventory |
| `license` (spdx, file) | Legal + trust signal. | inventory |
| `hotspots[]` | Files worth human eyes. | pipeline heuristics |

## performance

| Field | Why | Source |
|---|---|---|
| `timers[]` (intervalMs, repeat, spawnsProcess) | Battery/CPU; a tight timer that spawns processes is abusive. | opengrep (Timer) |
| `estSpawnsPerMin` | Quantifies process churn. | derived |
| `keepLoaded` | Always-resident cost: manifest `keepLoaded: true`, or a resident kind (bar-widget/bar/service). | manifest |
| `largeAssets[]` | Bundle bloat. | inventory |
| `polling[]` | Busy-polling evidence. | opengrep |

## maintenance

Last commit, commits/90d, contributors, open issues, archived, latest release.
Matters: an abandoned or archived plugin won't get security fixes. Source: gh API
(nulls when unavailable).

## diffSinceLastReview (`null` on first review)

fromCommit/toCommit, files/insertions/deletions, newFindings, resolvedRuleIds (opaque),
capabilityChanges, outcomeChange. Matters: on an update, shows exactly what changed
and whether risk rose -- the core defense against "reviewed benign, then push malware".
Source: `git diff` + `mal diff` + re-scan.

## findings[]

Ground truth. Each: path:line, snippet (<=400, redacted), severity, confidence,
category, `hardFail`, optional `aiVerified`. Every other section references these by id.

## ai

| Field | Why | Source |
|---|---|---|
| `pass1` | Whole-repo review: summary, oneLiner, additional findings, escalation request, injection observations. | AI pass 1 |
| `pass2[]` | Per-finding confirm/likely-fp/unsure re-check. Annotation only: never changes score or outcome. | AI pass 2 |
| `guard` (integrity checks + failures) | Whether the AI output could be trusted at all (any failed check discards all AI input), and why a pass produced none. | pipeline |
