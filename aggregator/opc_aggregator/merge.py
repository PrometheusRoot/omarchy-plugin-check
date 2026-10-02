"""Merge rules (ADR-0009, spec/PROTOCOL.md §5): effective verdict per row, combined verdict per plugin.

Pure and total. The same rules ship in the CLI and the store app; golden cases live in
tests/test_merge.py and are the contract.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from opc_spec import ids
from opc_spec.vocab import TRUSTED_TIERS, Verdict, cap, severity_rank, worst

from opc_aggregator.model import Combined, Effective, Row

if TYPE_CHECKING:
    from collections.abc import Iterable, Sequence

CAPPED_CEILING: Verdict = "caution"
CONTESTED_SPREAD = 2
"""Trusted rows this many levels apart (e.g. safe vs risky) mark the plugin contested."""


def effective(row: Row) -> Effective:
    """Apply the per-row rules: `blocked` needs file:line evidence; untrusted tiers cap at caution."""
    verdict: Verdict = row.verdict
    adjustments: list[str] = []
    if verdict == "blocked" and not row.has_evidence:
        verdict = "risky"
        adjustments.append("blocked-without-evidence")
    if row.tier not in TRUSTED_TIERS and severity_rank(verdict) > severity_rank(CAPPED_CEILING):
        verdict = cap(verdict, CAPPED_CEILING)
        adjustments.append("capped-at-caution")
    return Effective(verdict, tuple(adjustments))


def latest_per_provider(rows: Iterable[Row]) -> list[Row]:
    """Keep each provider's most recent row (by time reviewed; undated rows lose; ties keep the first)."""
    best: dict[str, Row] = {}
    for r in rows:
        cur = best.get(r.provider)
        if cur is None or _newer(r, cur):
            best[r.provider] = r
    return sorted(best.values(), key=lambda r: r.provider)


def _newer(a: Row, b: Row) -> bool:
    if a.time_reviewed is None:
        return False
    return b.time_reviewed is None or a.time_reviewed > b.time_reviewed


def _contested(trusted: Sequence[Row], capped: Sequence[Row]) -> bool:
    ranks = [severity_rank(r.verdict) for r in trusted if severity_rank(r.verdict) >= 0]
    if ranks and max(ranks) - min(ranks) >= CONTESTED_SPREAD:
        return True
    trusted_safe = any(r.verdict == "safe" for r in trusted)
    capped_bad = any(severity_rank(r.verdict) >= severity_rank("risky") for r in capped)
    return trusted_safe and capped_bad


def combine(rows: Sequence[Row]) -> Combined:
    """Worst-of the effective verdicts of the given rows (one per provider; see latest_per_provider).

    Invariants (property-tested): never more severe than the worst raw verdict; `blocked` only from
    a trusted row with evidence; without a trusted decided row the result is never `safe`;
    adding a row never makes the result less severe.
    """
    decided = [r for r in rows if severity_rank(r.verdict) >= 0]
    trusted = [r for r in decided if r.tier in TRUSTED_TIERS]
    capped = [r for r in decided if r.tier not in TRUSTED_TIERS]
    eff = {id(r): effective(r) for r in decided}
    verdict = worst([eff[id(r)].verdict for r in decided])
    reasons: list[str] = []
    for r in decided:
        e = eff[id(r)]
        if e.verdict == verdict:
            note = f" ({', '.join(e.adjustments)})" if e.adjustments else ""
            reasons.append(f"{r.provider} [{r.tier}]: {r.verdict}{note}")
    if trusted:
        basis = "trusted"
    elif capped:
        basis = "untrusted"
        if verdict == "safe":
            verdict = "unknown"
            reasons = ["no core or verified provider reviewed it; untrusted rows cannot make it safe"]
    else:
        basis = "none"
        reasons = ["no provider has a decided verdict"]
    commits = tuple(dict.fromkeys(r.commit for r in decided if r.commit))
    return Combined(verdict, basis, _contested(trusted, capped), commits, tuple(reasons[:20]))


def decided_tree(rows: Sequence[Row], combined: Combined) -> str | None:
    """The reviewed git tree of the commit that decided `combined`, or None.

    Only for a trusted basis at a single commit, and only when every trusted row of that commit
    that names a tree (the statement's `subject.digest.gitTree`) names the same one: the tree lets
    a client accept a re-signed or rebased commit with identical content (ADR-0034).
    """
    if combined.basis != "trusted" or len(combined.commits) != 1:
        return None
    commit = combined.commits[0]
    trees = {
        r.tree
        for r in rows
        if r.tier in TRUSTED_TIERS
        and r.commit == commit
        and severity_rank(r.verdict) >= 0
        and ids.is_sha1(r.tree)
    }
    return trees.pop() if len(trees) == 1 else None
