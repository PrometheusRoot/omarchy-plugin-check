"""Assemble store.json (spec/schemas/store.schema.json) from marketplace, verdicts, stats and ranking. Pure.

Inputs from the collector arrive as its documented JSON outputs (`stats.json`, `ranking.json`); the
aggregator never imports the collector (ADR-0026). Missing inputs degrade to nulls, never errors.
"""

from __future__ import annotations

from collections import Counter
from dataclasses import dataclass
from typing import TYPE_CHECKING, Any, cast

from opc_spec.jsonv import arr, obj, strs, text
from opc_spec.marketplace import manifest_dir

from opc_aggregator.model import Combined, Row, iso

if TYPE_CHECKING:
    import datetime as dt
    from collections.abc import Mapping, Sequence

    from opc_aggregator.marketplace import Marketplace, Plugin

KIND = "omarchy-plugin-check/store"
IMAGE_BASE = "https://plugins.omarchy.org/assets/img/plugins/"
IMAGE_PREFIX = "assets/img/plugins/"
MARKETPLACE_ORIGIN = "https://plugins.omarchy.org/"

GH_KEYS = (
    "stars",
    "vel30",
    "lastCommit",
    "c90",
    "contrib",
    "bus",
    "rel180",
    "lastRelease",
    "issues",
    "respH",
    "archived",
    "branch",
)
SHELF_KEYS = ("top", "trending", "new", "updated", "safePicks")
GALLERY_MAX = 8
REQUIRED = frozenset({"id", "name", "verdict"})


@dataclass(frozen=True)
class SnapshotMeta:
    """Snapshot envelope values decided by the caller."""

    now: dt.datetime
    version: int
    expires: dt.datetime
    dev: bool
    api_base: str
    image_base: str = IMAGE_BASE


def _str(raw: Mapping[str, Any], key: str, n: int) -> str | None:
    v = raw.get(key)
    return v[:n] if isinstance(v, str) else None


def _img(raw: Mapping[str, Any]) -> dict[str, Any] | None:
    thumb, full = raw.get("previewThumbnail"), raw.get("previewImage")
    if not isinstance(thumb, str) and not isinstance(full, str):
        return None
    out: dict[str, Any] = {}
    if isinstance(thumb, str):
        out["thumb"] = _image_ref(thumb)
    if isinstance(full, str):
        out["full"] = _image_ref(full)
    for src, dst in (("previewWidth", "w"), ("previewHeight", "h")):
        if isinstance(raw.get(src), int):
            out[dst] = raw[src]
    return out


def _image_ref(path: str) -> str:
    """Marketplace image path → imageBase-relative name, or an absolute https URL."""
    if path.startswith("https://"):
        return path
    rel = path.lstrip("/")
    return rel.removeprefix(IMAGE_PREFIX) if rel.startswith(IMAGE_PREFIX) else MARKETPLACE_ORIGIN + rel


def _when(raw: Mapping[str, Any], key: str) -> str | None:
    """Timestamp to the second ('2026-08-20T03:43:03.431Z' → '2026-08-20T03:43:03Z')."""
    v = _str(raw, key, 40)
    return v[:19] + "Z" if v and len(v) >= 19 and v[10] == "T" else v


def _install(plugin: Plugin) -> str | None:
    """None = the default `omarchy plugin add <repo>.git --enable`; '' = not installable."""
    raw = plugin.raw
    if raw.get("installAvailable") is False:
        return ""
    cmd = _str(raw, "installCommand", 300)
    return None if not cmd or cmd == f"omarchy plugin add {plugin.repo}.git --enable" else cmd


def _gh(repo_stats: Mapping[str, Any] | None) -> dict[str, Any] | None:
    if not repo_stats or not isinstance(repo_stats.get("stars"), int):
        return None
    return {k: repo_stats.get(k) for k in GH_KEYS} | {"archived": bool(repo_stats.get("archived"))}


def _gallery(repo_stats: Mapping[str, Any] | None, path: str) -> list[str]:
    """README images of the plugin directory (monorepos), else of the repository."""
    stats = obj(repo_stats)
    own = strs(obj(stats.get("dirImages")).get(path)) if path else []
    return (own or strs(stats.get("images")))[:GALLERY_MAX]


def _verdict(rows: Sequence[Row], combined: Combined | None) -> dict[str, Any]:
    """Compact verdict: `contested` only if true; `commit` only for a trusted basis at one commit."""
    if combined is None:
        return {"combined": "unknown", "basis": "none", "providers": {}}
    out: dict[str, Any] = {
        "combined": combined.verdict,
        "basis": combined.basis,
        "providers": {r.provider: r.verdict for r in rows},
    }
    if combined.contested:
        out["contested"] = True
    if combined.basis == "trusted" and len(combined.commits) == 1:
        out["commit"] = combined.commits[0]
    return out


def plugin_entry(  # noqa: PLR0913  # why: one row joins five independent sources
    plugin: Plugin,
    rows: Sequence[Row],
    combined: Combined | None,
    *,
    repo_stats: Mapping[str, Any] | None,
    engagement: Mapping[str, Any] | None,
    ranked: Mapping[str, Any] | None,
) -> dict[str, Any]:
    """One compact store.json plugin row."""
    raw = plugin.raw
    path = manifest_dir(raw)
    entry: dict[str, Any] = {
        "id": plugin.id,
        "name": plugin.name[:200],
        "author": _str(raw, "author", 200),
        "desc": _str(raw, "description", 1000),
        "cat": _str(raw, "category", 64),
        "kind": _str(raw, "kind", 64),
        "tags": [t[:64] for t in strs(raw.get("tags"))][:20],
        "repo": plugin.repo,
        "state": plugin.state,
        "verif": _str(raw, "verificationStatus", 32),
        "listed": _when(raw, "listedAt"),
        "updated": _when(raw, "repositoryUpdatedAt"),
        "img": _img(raw),
        "gallery": _gallery(repo_stats, path),
        "gh": _gh(repo_stats),
        "mkt": {k: int(engagement.get(k) or 0) for k in ("views", "copies", "hearts")}
        if engagement
        else None,
        "rank": (ranked or {}).get("rank"),
        "score": (ranked or {}).get("score"),
        "fac": [round(float(x), 1) for x in arr(obj(ranked).get("fac"))],
        "verdict": _verdict(rows, combined),
        "report": True if combined is not None else None,
        "path": path or None,
        "install": _install(plugin),
        "license": _str(raw, "license", 64),
        "version": _str(raw, "version", 64),
    }
    return {k: v for k, v in entry.items() if k in REQUIRED or not _empty(k, v)}


def _empty(key: str, value: object) -> bool:
    """Dropped to keep store.json compact: absent = null, [], or (state) listed."""
    return value is None or value == [] or (key == "state" and value == "listed")


def assemble(  # noqa: PLR0913  # why: the snapshot is a join of independent inputs
    meta: SnapshotMeta,
    market: Marketplace,
    rows: Mapping[str, Sequence[Row]],
    combined: Mapping[str, Combined],
    *,
    providers: Sequence[Mapping[str, Any]],
    stats: Mapping[str, Any] | None,
    ranking: Mapping[str, Any] | None,
) -> dict[str, Any]:
    """The whole store.json document."""
    repos = cast("Mapping[str, Any]", (stats or {}).get("repos") or {})
    engagement = cast("Mapping[str, Any]", (stats or {}).get("engagement") or {})
    ranked = cast("Mapping[str, Any]", (ranking or {}).get("plugins") or {})
    plugins = [
        plugin_entry(
            p,
            rows.get(p.id, ()),
            combined.get(p.id),
            repo_stats=repos.get(p.repo_key) if p.repo_key else None,
            engagement=engagement.get(p.id),
            ranked=ranked.get(p.id),
        )
        for p in sorted(market.plugins.values(), key=lambda p: p.id)
    ]
    states = Counter(p.state for p in market.plugins.values())
    listed = [p for p in market.plugins.values() if p.state == "listed"]
    cats = Counter(c for c in (text(p.raw.get("category")) for p in listed) if c)
    shelves = cast("Mapping[str, Any]", (ranking or {}).get("shelves") or {})
    return {
        "schemaVersion": 1,
        "kind": KIND,
        "version": meta.version,
        "generatedAt": iso(meta.now),
        "expires": iso(meta.expires),
        "dev": meta.dev,
        "catalog": {
            "generatedAt": market.generated_at,
            "plugins": len(market.plugins),
            "retired": states["retired"],
            "builtin": states["builtin"],
        },
        "imageBase": meta.image_base,
        "apiBase": meta.api_base,
        "providers": [
            {k: p[k] for k in ("id", "name", "tier", "verification")} | {"rows": p["rows"]} for p in providers
        ],
        "ranking": {
            "version": (ranking or {}).get("version", "none"),
            "factors": list((ranking or {}).get("factors") or []),
            "gates": dict((ranking or {}).get("gates") or {}),
            "statsGeneratedAt": (stats or {}).get("generatedAt"),
        },
        "shelves": {k: list(shelves.get(k) or [])[:100] for k in SHELF_KEYS}
        | {"byCategory": {c: strs(v)[:100] for c, v in obj(shelves.get("byCategory")).items()}},
        "categories": [
            {"name": c, "count": n} for c, n in sorted(cats.items(), key=lambda kv: (-kv[1], kv[0]))
        ],
        "plugins": plugins,
    }
