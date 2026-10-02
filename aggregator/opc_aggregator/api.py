"""Render the static API documents (spec/schemas/api-*.schema.json). Pure."""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from opc_spec import ids
from opc_spec.vocab import VERDICTS

from opc_aggregator.merge import effective
from opc_aggregator.model import Combined, Row, iso

if TYPE_CHECKING:
    import datetime as dt
    from collections.abc import Mapping, Sequence

    from opc_aggregator.marketplace import Marketplace, Plugin

API_VERSION = "v1"
WEEKS = 52


def row_doc(row: Row) -> dict[str, Any]:
    """One api-plugin row."""
    eff = effective(row)
    doc: dict[str, Any] = {
        "provider": row.provider,
        "tier": row.tier,
        "verification": row.verification,
        "signer": row.signer,
        "signedAt": iso(row.signed_at) if row.signed_at else None,
        "commit": row.commit,
        "tree": row.tree,
        "verdict": row.verdict,
        "effectiveVerdict": eff.verdict,
        "adjustments": list(eff.adjustments),
        "counted": row.verdict in VERDICTS,
        "timeReviewed": iso(row.time_reviewed) if row.time_reviewed else None,
        "statement": row.statement,
    }
    if row.summary:
        doc["summary"] = row.summary[:200]
    if row.criteria is not None:
        doc["criteria"] = dict(row.criteria)
    if row.findings:
        doc["findings"] = [dict(f) for f in row.findings]
    if row.detail:
        doc["detail"] = dict(row.detail)
    return doc


def combined_doc(c: Combined) -> dict[str, Any]:
    """The api-plugin `combined` object."""
    return {
        "verdict": c.verdict,
        "basis": c.basis,
        "contested": c.contested,
        "commits": list(c.commits),
        "reasons": list(c.reasons),
    }


def plugin_doc(
    plugin: Plugin,
    rows: Sequence[Row],
    combined: Combined,
    *,
    listing: Mapping[str, Any] | None = None,
    weeks: Sequence[int | None] | None = None,
) -> dict[str, Any]:
    """api/v1/plugins/<id>.json; with a snapshot also the full store row and weekly commits."""
    extra: dict[str, Any] = {}
    if listing is not None:
        extra["listing"] = dict(listing)
    if weeks is not None and len(weeks) == WEEKS:
        extra["activity"] = {"weeks": list(weeks)}
    return {
        "schemaVersion": 1,
        "id": plugin.id,
        "name": plugin.name[:200],
        "repo": plugin.repo,
        "listingState": plugin.state,
        "marketplaceUrl": ids.marketplace_url(plugin.id),
        "combined": combined_doc(combined),
        "providers": [row_doc(r) for r in rows],
    } | extra


def quality_of(rows: Sequence[Row]) -> int | None:
    """Quality score from the most trusted row that has one (core first, then verified, ...)."""
    order = {"core": 0, "verified": 1, "community": 2, "unsigned": 3}
    scored = sorted((order[r.tier], r.provider, r.quality) for r in rows if r.quality is not None)
    return scored[0][2] if scored else None


def index_doc(entries: Sequence[tuple[Plugin, Sequence[Row], Combined]], now: dt.datetime) -> dict[str, Any]:
    """api/v1/index.json: one row per plugin with any provider row."""
    plugins = [
        {
            "id": p.id,
            "repo": p.repo,
            "verdict": c.verdict,
            "basis": c.basis,
            "contested": c.contested,
            "quality": quality_of(rows),
            "providers": {r.provider: r.verdict for r in rows},
            "path": f"plugins/{p.id}.json",
        }
        for p, rows, c in entries
        if p.repo
    ]
    return {"schemaVersion": 1, "generatedAt": iso(now), "plugins": plugins}


def by_repo_doc(market: Marketplace, now: dt.datetime) -> dict[str, Any]:
    """api/v1/by-repo.json."""
    return {"schemaVersion": 1, "generatedAt": iso(now), "repos": market.by_repo()}


def counts(combined: Sequence[Combined]) -> dict[str, int]:
    """Combined verdict histogram (all five values present)."""
    out = dict.fromkeys([*VERDICTS, "unknown"], 0)
    for c in combined:
        out[c.verdict] += 1
    return out


def meta_doc(  # noqa: PLR0913  # why: one flat document, every field is a separate input
    *,
    now: dt.datetime,
    predicate_type: str,
    market: Marketplace,
    registry: Mapping[str, Any],
    providers: Sequence[Mapping[str, Any]],
    combined: Sequence[Combined],
    rejected: Sequence[Mapping[str, str]],
) -> dict[str, Any]:
    """api/v1/meta.json."""
    return {
        "schemaVersion": 1,
        "apiVersion": API_VERSION,
        "generatedAt": iso(now),
        "predicateType": predicate_type,
        "catalogGeneratedAt": market.generated_at,
        "registry": dict(registry),
        "providers": [dict(p) for p in providers],
        "pluginCount": len(combined),
        "counts": counts(combined),
        "rejected": [dict(r) for r in rejected[:1000]],
    }
