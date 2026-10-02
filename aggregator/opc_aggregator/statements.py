"""Turn a verified, admitted in-toto statement into a provider Row. Pure."""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from opc_spec.jsonv import integer, obj, objs
from opc_spec.vocab import as_verdict

from opc_aggregator.model import Row, parse_time

if TYPE_CHECKING:
    from collections.abc import Mapping, Sequence

    from opc_aggregator.model import Provider
    from opc_aggregator.ports import Verified


def has_line_evidence(findings: Sequence[Mapping[str, Any]]) -> bool:
    """True if some `blocking` finding has a location with a start line (required for `blocked`)."""
    return any(
        f.get("blocking") is True and any(integer(loc.get("startLine")) for loc in objs(f.get("locations")))
        for f in findings
    )


def statement_path(plugin_id: str, provider_id: str, commit: str) -> str:
    """API-relative path of a verified statement (immutable once written)."""
    return f"plugins/{plugin_id}/{provider_id}/{commit}.json"


def row_from_statement(stmt: Mapping[str, Any], provider: Provider, verified: Verified) -> Row:
    """Row for a schema-valid, admitted statement."""
    pred = stmt["predicate"]
    digest = stmt["subject"][0]["digest"]
    findings = tuple(pred.get("findings") or ())
    quality = integer(obj(pred.get("quality")).get("score"))
    return Row(
        provider=provider.id,
        tier=provider.tier,
        verification=verified.verification,
        verdict=as_verdict(pred["verdict"]),
        has_evidence=has_line_evidence(findings),
        commit=digest["gitCommit"],
        tree=digest.get("gitTree"),
        time_reviewed=parse_time(pred["timeReviewed"]),
        signer=verified.signer,
        signed_at=verified.signed_at,
        summary=pred.get("summary"),
        criteria=pred.get("criteria"),
        findings=findings,
        quality=quality,
        detail={
            "scope": pred.get("scope"),
            "method": pred["provider"].get("method"),
            "target": pred["plugin"].get("target"),
        },
        statement=statement_path(pred["plugin"]["id"], provider.id, digest["gitCommit"]),
    )
