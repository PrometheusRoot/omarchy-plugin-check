"""Value types of the aggregator: the provider registry, one provider row, the combined verdict.

Pure: parsing assumes the document already validated against its spec schema.
"""

from __future__ import annotations

import datetime as dt
from dataclasses import dataclass, field
from typing import TYPE_CHECKING, Any, Literal

from opc_spec.jsonv import obj, objs, strs, text

if TYPE_CHECKING:
    from collections.abc import Mapping

    from opc_spec.vocab import Tier, Verdict

Verification = Literal["sigstore", "unsigned-dev", "unsigned"]
Basis = Literal["trusted", "untrusted", "none"]


def parse_time(value: str) -> dt.datetime:
    """RFC 3339 → aware UTC datetime. Raises ValueError for a naive or malformed timestamp."""
    t = dt.datetime.fromisoformat(value)
    if t.tzinfo is None:
        raise ValueError(f"timestamp without timezone: {value!r}")
    return t.astimezone(dt.UTC)


def iso(t: dt.datetime) -> str:
    """Aware datetime → 'YYYY-MM-DDTHH:MM:SSZ' (UTC, seconds)."""
    return t.astimezone(dt.UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


@dataclass(frozen=True)
class Window:
    """A half-open time window [start, end) with the reason it exists."""

    start: dt.datetime
    end: dt.datetime
    reason: str

    def contains(self, t: dt.datetime) -> bool:
        """True if `t` falls inside the window."""
        return self.start <= t < self.end


@dataclass(frozen=True)
class Provider:
    """One registry entry (providers.schema.json)."""

    id: str
    name: str
    kind: Literal["feed", "marketplace-baseline"]
    tier: Tier
    feed_url: str
    signing: Literal["sigstore", "none"]
    issuer: str | None
    identity: str | None
    repository: str | None
    valid_from: dt.datetime
    valid_until: dt.datetime | None
    excluded: tuple[Window, ...] = ()
    conflicts: frozenset[str] = frozenset()


@dataclass(frozen=True)
class Registry:
    """providers.json: versioned, expiring, optionally a dev registry."""

    version: int
    generated_at: dt.datetime
    expires: dt.datetime
    predicate_type: str
    dev: bool
    providers: tuple[Provider, ...]


def parse_provider(doc: Mapping[str, Any]) -> Provider:
    """One provider entry → Provider."""
    sig = obj(doc.get("sigstore"))
    return Provider(
        id=doc["id"],
        name=doc["name"],
        kind=doc["kind"],
        tier=doc["tier"],
        feed_url=doc["feedUrl"],
        signing=doc["signing"],
        issuer=text(sig.get("oidcIssuer")),
        identity=text(sig.get("certificateIdentity")),
        repository=text(sig.get("repository")),
        valid_from=parse_time(doc["validFrom"]),
        valid_until=parse_time(doc["validUntil"]) if doc.get("validUntil") else None,
        excluded=tuple(
            Window(parse_time(w["from"]), parse_time(w["until"]), str(w["reason"]))
            for w in objs(doc.get("excludedWindows"))
        ),
        conflicts=frozenset(c.lower() for c in strs(doc.get("conflictsOfInterest"))),
    )


def parse_registry(doc: Mapping[str, Any]) -> Registry:
    """A schema-valid providers.json document → Registry."""
    return Registry(
        version=int(doc["version"]),
        generated_at=parse_time(doc["generatedAt"]),
        expires=parse_time(doc["expires"]),
        predicate_type=doc["predicateType"],
        dev=bool(doc.get("dev", False)),
        providers=tuple(parse_provider(p) for p in doc["providers"]),
    )


@dataclass(frozen=True)
class Row:
    """One provider's latest conclusion about one plugin (an api-plugin row before rendering)."""

    provider: str
    tier: Tier
    verification: Verification
    verdict: Verdict
    has_evidence: bool
    commit: str | None
    time_reviewed: dt.datetime | None
    tree: str | None = None
    signer: str | None = None
    signed_at: dt.datetime | None = None
    summary: str | None = None
    criteria: Mapping[str, Any] | None = None
    findings: tuple[Mapping[str, Any], ...] = ()
    quality: int | None = None
    detail: Mapping[str, Any] = field(default_factory=dict[str, Any])
    statement: str | None = None


@dataclass(frozen=True)
class Effective:
    """A row's verdict after the merge rules, with the rules that changed it."""

    verdict: Verdict
    adjustments: tuple[str, ...]


@dataclass(frozen=True)
class Combined:
    """The combined verdict for one plugin (ADR-0009)."""

    verdict: Verdict
    basis: Basis
    contested: bool
    commits: tuple[str, ...]
    reasons: tuple[str, ...]
