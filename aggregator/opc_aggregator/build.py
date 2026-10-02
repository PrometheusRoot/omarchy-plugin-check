"""Aggregate: registry → feeds → verified, admitted rows → per-plugin combined verdicts.

Imperative shell over the pure rules in admit/merge/statements/marketplace. All I/O goes through the
Fetcher and Verifier ports, so tests run it end to end with local files and fake verifiers.
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass, field
from typing import TYPE_CHECKING, Any

from opc_spec import schemas

from opc_aggregator import admit, marketplace
from opc_aggregator.merge import combine, latest_per_provider
from opc_aggregator.model import Combined, Provider, Registry, Row, iso, parse_registry, parse_time
from opc_aggregator.ports import FetchError, VerificationError
from opc_aggregator.statements import row_from_statement

if TYPE_CHECKING:
    import datetime as dt
    from collections.abc import Mapping
    from pathlib import Path

    from opc_aggregator.ports import Fetcher, Verifier
    from opc_aggregator.state import State


class RegistryError(Exception):
    """The provider registry itself is unusable (expired, rolled back, invalid)."""


@dataclass
class ProviderStatus:
    """Outcome of reading one provider (api/v1/meta.json providers[])."""

    provider: Provider
    verification: str
    feed_version: int | None = None
    feed_expires: str | None = None
    rows: int = 0
    status: str = "ok"

    def doc(self) -> dict[str, Any]:
        """meta.json provider entry."""
        return {
            "id": self.provider.id,
            "name": self.provider.name,
            "tier": self.provider.tier,
            "verification": self.verification,
            "feedVersion": self.feed_version,
            "feedExpires": self.feed_expires,
            "rows": self.rows,
            "status": self.status,
        }


@dataclass
class Aggregate:
    """Everything publish needs."""

    registry: Registry
    market: marketplace.Marketplace
    rows: dict[str, list[Row]] = field(default_factory=dict[str, list[Row]])
    combined: dict[str, Combined] = field(default_factory=dict[str, Combined])
    statements: dict[str, bytes] = field(default_factory=dict[str, bytes])
    providers: list[ProviderStatus] = field(default_factory=list[ProviderStatus])
    rejected: list[dict[str, str]] = field(default_factory=list[dict[str, str]])


@dataclass(frozen=True)
class Inputs:
    """What one aggregation run reads."""

    registry_doc: Mapping[str, Any]
    catalog: Mapping[str, Any]
    market_registry: Mapping[str, Any] | None
    now: dt.datetime
    base_dir: Path | None = None
    """Directory that relative (dev) feed URLs resolve against."""


def _join(root: str, rel: str) -> str:
    return root.rstrip("/") + "/" + rel


def _feed_root(provider: Provider, inp: Inputs) -> str:
    if provider.feed_url.startswith("https://") or inp.base_dir is None:
        return provider.feed_url
    return str((inp.base_dir / provider.feed_url).resolve())


def load_registry(inp: Inputs, st: State) -> Registry:
    """Validate and admit providers.json; raise RegistryError."""
    errs = schemas.errors(inp.registry_doc, "providers")
    if errs:
        raise RegistryError("providers.json invalid: " + "; ".join(errs[:3]))
    reg = parse_registry(inp.registry_doc)
    reason = admit.registry_reason(reg, inp.now, st.registry)
    if reason:
        raise RegistryError(reason)
    return reg


def aggregate(inp: Inputs, fetcher: Fetcher, verifiers: Mapping[str, Verifier], st: State) -> Aggregate:
    """Run one aggregation. Updates `st` with the accepted feed versions (caller saves it)."""
    reg = load_registry(inp, st)
    market = marketplace.parse(inp.catalog, inp.market_registry)
    agg = Aggregate(registry=reg, market=market)
    for provider in reg.providers:
        if provider.kind == "marketplace-baseline":
            _read_baseline(agg, provider, inp)
        else:
            _read_feed(agg, provider, inp=inp, fetcher=fetcher, verifiers=verifiers, st=st)
    for pid, rows in agg.rows.items():
        latest = latest_per_provider(rows)
        agg.rows[pid] = latest
        agg.combined[pid] = combine(latest)
    st.registry = reg.version
    return agg


def _read_baseline(agg: Aggregate, provider: Provider, inp: Inputs) -> None:
    status = ProviderStatus(provider, "unsigned")
    agg.providers.append(status)
    if inp.market_registry is None:
        status.status = "marketplace registry.json not provided"
        return
    rows = marketplace.baseline_rows(inp.market_registry, agg.market, provider)
    for pid, row in rows.items():
        agg.rows.setdefault(pid, []).append(row)
    status.rows = len(rows)


def _verifier_for(
    provider: Provider, reg: Registry, verifiers: Mapping[str, Verifier]
) -> tuple[Verifier | None, str]:
    if provider.signing == "sigstore":
        return verifiers.get("sigstore"), "sigstore"
    if reg.dev:
        return verifiers.get("none"), "unsigned-dev"
    return None, "unsigned-dev"


def _read_feed(  # noqa: PLR0913  # why: the run context is passed explicitly, no globals
    agg: Aggregate,
    provider: Provider,
    *,
    inp: Inputs,
    fetcher: Fetcher,
    verifiers: Mapping[str, Verifier],
    st: State,
) -> None:
    verifier, method = _verifier_for(provider, agg.registry, verifiers)
    status = ProviderStatus(provider, method)
    agg.providers.append(status)
    if verifier is None:
        status.status = "unsigned provider outside a dev registry" if method != "sigstore" else "no verifier"
        return
    root = _join(_feed_root(provider, inp), "feed/v1")
    try:
        raw = fetcher.get(_join(root, "index.json"))
        bundle = (
            fetcher.get(_join(root, "index.json.sigstore.json")) if provider.signing == "sigstore" else None
        )
        verifier.verify_blob(provider, raw, bundle)
        index: dict[str, Any] = json.loads(raw)
    except (FetchError, VerificationError, ValueError) as exc:
        status.status = f"index rejected: {exc}"[:300]
        return
    errs = schemas.errors(index, "feed-index")
    reason = ("index invalid: " + "; ".join(errs[:3])) if errs else None
    reason = reason or admit.feed_reason(
        index, provider, agg.registry.predicate_type, inp.now, st.feeds.get(provider.id)
    )
    if reason:
        status.status = reason[:300]
        return
    status.feed_version, status.feed_expires = int(index["version"]), index["expires"]
    for entry in index["entries"]:
        row_reason = _read_entry(agg, provider, entry, root=root, fetcher=fetcher, verifier=verifier)
        if row_reason:
            agg.rejected.append({"provider": provider.id, "path": entry["path"], "reason": row_reason[:300]})
        else:
            status.rows += 1
    st.feeds[provider.id] = int(index["version"])


def _read_entry(  # noqa: PLR0913  # why: explicit run context
    agg: Aggregate,
    provider: Provider,
    entry: Mapping[str, Any],
    *,
    root: str,
    fetcher: Fetcher,
    verifier: Verifier,
) -> str | None:
    try:
        data = fetcher.get(_join(root, entry["path"]))
        if hashlib.sha256(data).hexdigest() != entry["sha256"]:
            return "sha256 does not match the index"
        verified = verifier.verify_attestation(provider, data)
        stmt: dict[str, Any] = json.loads(verified.payload)
    except (FetchError, VerificationError, ValueError) as exc:
        return str(exc)
    errs = schemas.errors(stmt, "statement")
    if errs:
        return "statement invalid: " + "; ".join(errs[:3])
    reason = admit.statement_reason(stmt, entry, provider, agg.market, agg.registry.predicate_type)
    signed_at = verified.signed_at or parse_time(stmt["predicate"]["timeReviewed"])
    reason = reason or admit.signing_time_reason(provider, signed_at)
    if reason:
        return reason
    row = row_from_statement(stmt, provider, verified)
    agg.rows.setdefault(entry["pluginId"], []).append(row)
    if row.statement:
        agg.statements[row.statement] = verified.payload
    return None


def registry_summary(reg: Registry, *, signed: bool) -> dict[str, Any]:
    """meta.json `registry` object."""
    return {"version": reg.version, "expires": iso(reg.expires), "dev": reg.dev, "signed": signed}
