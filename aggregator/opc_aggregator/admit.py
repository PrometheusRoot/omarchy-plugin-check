"""Admission rules: what a consumer rejects before a row may exist (spec/PROTOCOL.md §5).

Pure. Every function returns `None` when the input is admitted, else a short reason string that ends
up in api/v1/meta.json (`rejected[]` / provider `status`).
"""

from __future__ import annotations

import datetime as dt
from typing import TYPE_CHECKING, Any

from opc_spec import ids

from opc_aggregator.model import Provider, Registry, parse_time

if TYPE_CHECKING:
    from collections.abc import Mapping

    from opc_aggregator.marketplace import Marketplace

MAX_FEED_VALIDITY = dt.timedelta(days=30)


def registry_reason(reg: Registry, now: dt.datetime, last_version: int | None) -> str | None:
    """Reject an expired registry or one older than the last accepted version."""
    if reg.expires <= now:
        return f"registry expired at {reg.expires.isoformat()}"
    if last_version is not None and reg.version < last_version:
        return f"registry rollback: version {reg.version} < last accepted {last_version}"
    return None


def feed_reason(
    index: Mapping[str, Any],
    provider: Provider,
    predicate_type: str,
    now: dt.datetime,
    last_version: int | None,
) -> str | None:
    """Reject a feed index for another provider/predicate, expired, over-long, or rolled back."""
    if index["provider"] != provider.id:
        return f"index is for provider {index['provider']!r}"
    if index["predicateType"] != predicate_type:
        return f"predicateType {index['predicateType']!r} is not {predicate_type!r}"
    generated, expires = parse_time(index["generatedAt"]), parse_time(index["expires"])
    if expires <= now:
        return f"feed expired at {index['expires']}"
    if expires - generated > MAX_FEED_VALIDITY:
        return "feed validity exceeds 30 days"
    if last_version is not None and int(index["version"]) < last_version:
        return f"feed rollback: version {index['version']} < last accepted {last_version}"
    return None


def signing_time_reason(provider: Provider, t: dt.datetime) -> str | None:
    """Reject a signature made outside the provider's validity or inside an excluded window."""
    if t < provider.valid_from:
        return f"signed {t.isoformat()} before validFrom"
    if provider.valid_until is not None and t >= provider.valid_until:
        return f"signed {t.isoformat()} after validUntil"
    for w in provider.excluded:
        if w.contains(t):
            return f"signed inside excluded window ({w.reason})"
    return None


def statement_reason(
    stmt: Mapping[str, Any],
    entry: Mapping[str, Any],
    provider: Provider,
    market: Marketplace,
    predicate_type: str,
) -> str | None:
    """Reject a schema-valid statement that does not match its index entry, provider or the marketplace."""
    pred = stmt["predicate"]
    subject = stmt["subject"][0]
    reason = None
    if stmt["predicateType"] != predicate_type:
        reason = "predicateType mismatch"
    elif pred["provider"]["id"] != provider.id:
        reason = f"statement names provider {pred['provider']['id']!r}"
    elif pred["plugin"]["id"] != entry["pluginId"] or subject["digest"]["gitCommit"] != entry["commit"]:
        reason = "statement does not match its index entry"
    return reason or _marketplace_reason(pred["plugin"]["id"], subject["name"], provider, market)


def _marketplace_reason(
    plugin_id: str, subject_name: str, provider: Provider, market: Marketplace
) -> str | None:
    plugin = market.plugins.get(plugin_id)
    if plugin is None:
        return "plugin is not listed on the marketplace (unlisted)"
    if plugin.state != "listed":
        return f"plugin is {plugin.state}; not reviewed"
    key = ids.repo_key(subject_name)
    if key is None or plugin.repo_key is None or market.canonical(key) != plugin.repo_key:
        return "subject repository is not the marketplace repository of this plugin"
    owner = plugin.repo_key.split("/", 1)[0]
    if plugin_id.lower() in provider.conflicts or owner in provider.conflicts:
        return "provider declared a conflict of interest"
    return None
