"""Marketplace sync: catalog.json, registry.json and the public engagement stats, cached.

The catalog and registry are the only plugin universe (ADR-0010). Every fetch is a conditional GET
into the collector cache, and engagement is fetched at most once per ENGAGEMENT_TTL.
"""

from __future__ import annotations

import datetime as dt
import json
from dataclasses import dataclass
from typing import TYPE_CHECKING, Any, Final

from opc_spec import marketplace
from opc_spec.jsonv import integer, obj, text

if TYPE_CHECKING:
    from collections.abc import Mapping
    from pathlib import Path

    from opc_collector.ports import Http

CATALOG_URL: Final = "https://plugins.omarchy.org/catalog.json"
REGISTRY_URL: Final = "https://raw.githubusercontent.com/omacom/omarchy-plugin-marketplace/main/registry.json"
ENGAGEMENT_URL: Final = "https://api.omarchyplugins.com/v1/stats"
ENGAGEMENT_TTL: Final = dt.timedelta(hours=20)


@dataclass(frozen=True)
class Fetched:
    """A cached document and whether this run downloaded it."""

    path: Path
    downloaded: bool


def fetch_cached(http: Http, url: str, dest: Path) -> Fetched:
    """Conditional GET into `dest` (validators kept in `<dest>.meta.json`); 304 keeps the cache."""
    meta_path = dest.with_name(dest.name + ".meta.json")
    meta = (
        obj(json.loads(meta_path.read_text(encoding="utf-8")))
        if meta_path.is_file() and dest.is_file()
        else {}
    )
    resp = http.get(url, text(meta.get("etag")), text(meta.get("lastModified")))
    if resp.body is not None:
        json.loads(resp.body)  # refuse to cache something that is not JSON
        dest.parent.mkdir(parents=True, exist_ok=True)
        tmp = dest.with_name(dest.name + ".tmp")
        tmp.write_bytes(resp.body)
        tmp.replace(dest)
    meta_path.write_text(
        json.dumps(
            {
                "url": url,
                "etag": resp.etag,
                "lastModified": resp.last_modified,
                "fetchedAt": dt.datetime.now(dt.UTC).isoformat(),
            }
        ),
        encoding="utf-8",
    )
    return Fetched(dest, downloaded=resp.body is not None)


def summary(catalog: Mapping[str, Any], registry: Mapping[str, Any] | None) -> dict[str, Any]:
    """Counts that describe a marketplace snapshot (printed by `opc-collect sync`)."""
    m = marketplace.parse(catalog, registry)
    states = [p.state for p in m.plugins.values()]
    return {
        "generatedAt": m.generated_at,
        "plugins": len(m.plugins),
        "listed": states.count("listed"),
        "retired": states.count("retired"),
        "builtin": states.count("builtin"),
        "retiredIds": len(obj(registry).get("retiredPluginIds") or []),
        "migrations": len(m.migrations),
        "repos": len({p.repo_key for p in m.plugins.values() if p.repo_key and p.state == "listed"}),
    }


def parse_engagement(doc: Mapping[str, Any]) -> dict[str, dict[str, int]]:
    """api.omarchyplugins.com/v1/stats → {plugin id: {views, copies, hearts}} (non-negative ints)."""
    out: dict[str, dict[str, int]] = {}
    for pid, row in obj(doc.get("plugins")).items():
        r = obj(row)
        out[pid] = {k: max(0, integer(r.get(k)) or 0) for k in ("views", "copies", "hearts")}
    return out


def engagement(http: Http, cache_dir: Path, now: dt.datetime) -> tuple[dict[str, dict[str, int]], str | None]:
    """Engagement per plugin and when it was fetched; refetched at most every ENGAGEMENT_TTL."""
    dest = cache_dir / "engagement.json"
    meta_path = dest.with_name(dest.name + ".meta.json")
    meta = obj(json.loads(meta_path.read_text(encoding="utf-8"))) if meta_path.is_file() else {}
    fetched = text(meta.get("fetchedAt"))
    stale = fetched is None or now - dt.datetime.fromisoformat(fetched) >= ENGAGEMENT_TTL
    if stale or not dest.is_file():
        fetch_cached(http, ENGAGEMENT_URL, dest)
        meta = obj(json.loads(meta_path.read_text(encoding="utf-8")))
    doc = obj(json.loads(dest.read_text(encoding="utf-8")))
    return parse_engagement(doc), text(meta.get("fetchedAt"))
