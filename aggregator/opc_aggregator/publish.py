"""Write the static API (api/v1/), the signed store snapshot and the store app's client bundle."""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from typing import TYPE_CHECKING, Any

from opc_spec import schemas
from opc_spec.vocab import BUNDLE_FILES, SNAPSHOT_NAMESPACE

from opc_aggregator import api, client, sshsig
from opc_aggregator.build import registry_summary
from opc_aggregator.merge import combine

if TYPE_CHECKING:
    import datetime as dt
    from collections.abc import Mapping, Sequence
    from pathlib import Path

    from opc_aggregator.build import Aggregate
    from opc_aggregator.model import Row


class PublishError(Exception):
    """A document we were about to publish failed its schema."""


def _dump(path: Path, doc: object, *, schema: str | None = None) -> bytes:
    """Validate (optionally), write atomically, return the exact bytes written."""
    if schema:
        errs = schemas.errors(doc, schema)
        if errs:
            raise PublishError(f"{path.name} [{schema}]: " + "; ".join(errs[:3]))
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    data = json.dumps(doc, ensure_ascii=False, separators=(",", ":")).encode()
    tmp.write_bytes(data)
    tmp.replace(path)
    return data


@dataclass(frozen=True)
class Listings:
    """Per-plugin snapshot extras for the detail documents (ADR-0032)."""

    rows: Mapping[str, Mapping[str, Any]]
    """store.json row per plugin id; every plugin with a row gets a detail document."""
    weeks: Mapping[str, Sequence[int | None]]
    """Weekly commits per plugin id (from the collector's stats)."""


def write_api(
    agg: Aggregate,
    api_dir: Path,
    now: dt.datetime,
    *,
    registry_signed: bool,
    listings: Listings | None = None,
) -> tuple[dict[str, Any], dict[str, str]]:
    """Write meta, index, by-repo, plugins/<id>.json and verified statements.

    Returns the index doc and {plugin id: sha256 of its detail document}. With `listings` (a snapshot
    build) every plugin that has a store row gets a detail document, reviewed or not.
    """
    entries = [
        (agg.market.plugins[pid], agg.rows[pid], agg.combined[pid])
        for pid in sorted(agg.combined)
        if pid in agg.market.plugins
    ]
    extra = sorted(set(listings.rows) - set(agg.combined)) if listings else []
    bare: list[Row] = []
    docs = [
        *entries,
        *((agg.market.plugins[pid], bare, combine(bare)) for pid in extra if pid in agg.market.plugins),
    ]
    hashes: dict[str, str] = {}
    for plugin, rows, combined in docs:
        data = _dump(
            api_dir / "plugins" / f"{plugin.id}.json",
            api.plugin_doc(
                plugin,
                rows,
                combined,
                listing=listings.rows.get(plugin.id) if listings else None,
                weeks=listings.weeks.get(plugin.id) if listings else None,
            ),
            schema="api-plugin",
        )
        hashes[plugin.id] = hashlib.sha256(data).hexdigest()
    for rel, payload in sorted(agg.statements.items()):
        out = api_dir / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(payload)
    index = api.index_doc(entries, now)
    _dump(api_dir / "index.json", index, schema="api-index")
    _dump(api_dir / "by-repo.json", api.by_repo_doc(agg.market, now), schema="api-by-repo")
    meta = api.meta_doc(
        now=now,
        predicate_type=agg.registry.predicate_type,
        market=agg.market,
        registry=registry_summary(agg.registry, signed=registry_signed),
        providers=[p.doc() for p in agg.providers],
        combined=[c for _, _, c in entries],
        rejected=agg.rejected,
    )
    _dump(api_dir / "meta.json", meta, schema="api-meta")
    return index, hashes


def write_store(doc: dict[str, Any], out: Path, key: Path | None) -> tuple[Path, Path | None]:
    """Validate and write store.json; sign it (store.json.sig) when a key is given."""
    store = out / "store.json"
    _dump(store, doc, schema="store")
    sig = sshsig.sign(store, key, SNAPSHOT_NAMESPACE) if key else None
    return store, sig


def write_bundle(
    store: Mapping[str, Any], hashes: Mapping[str, str], out: Path, key: Path | None
) -> tuple[Path, Path | None]:
    """Write the store app's client bundle next to store.json and sign its manifest (ADR-0032).

    The manifest commits to home, search, details and store.json (written before) by sha256;
    detail documents are committed through store-details.json.
    """
    files: list[tuple[str, str, bytes]] = []
    for role, schema, doc in (
        ("home", "store-home", client.home_doc(store)),
        ("search", "store-search", client.search_doc(store, hashes)),
        ("details", "store-details", client.details_doc(store["version"], hashes)),
    ):
        path = BUNDLE_FILES[role]
        files.append((role, path, _dump(out / path, doc, schema=schema)))
    files.append(("store", "store.json", (out / "store.json").read_bytes()))
    manifest = out / BUNDLE_FILES["manifest"]
    _dump(manifest, client.manifest_doc(store, files), schema="store-manifest")
    sig = sshsig.sign(manifest, key, SNAPSHOT_NAMESPACE) if key else None
    return manifest, sig
