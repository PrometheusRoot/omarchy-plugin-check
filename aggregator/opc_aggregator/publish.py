"""Write the static API (api/v1/) and the signed store snapshot to disk."""

from __future__ import annotations

import json
from typing import TYPE_CHECKING, Any

from opc_spec import schemas
from opc_spec.vocab import SNAPSHOT_NAMESPACE

from opc_aggregator import api, sshsig
from opc_aggregator.build import registry_summary

if TYPE_CHECKING:
    import datetime as dt
    from pathlib import Path

    from opc_aggregator.build import Aggregate


class PublishError(Exception):
    """A document we were about to publish failed its schema."""


def _dump(path: Path, doc: object, *, schema: str | None = None) -> None:
    if schema:
        errs = schemas.errors(doc, schema)
        if errs:
            raise PublishError(f"{path.name} [{schema}]: " + "; ".join(errs[:3]))
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(doc, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    tmp.replace(path)


def write_api(agg: Aggregate, api_dir: Path, now: dt.datetime, *, registry_signed: bool) -> dict[str, Any]:
    """Write meta, index, by-repo, plugins/<id>.json and verified statements; return the index doc."""
    entries = [
        (agg.market.plugins[pid], agg.rows[pid], agg.combined[pid])
        for pid in sorted(agg.combined)
        if pid in agg.market.plugins
    ]
    for plugin, rows, combined in entries:
        _dump(
            api_dir / "plugins" / f"{plugin.id}.json",
            api.plugin_doc(plugin, rows, combined),
            schema="api-plugin",
        )
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
    return index


def write_store(doc: dict[str, Any], out: Path, key: Path | None) -> tuple[Path, Path | None]:
    """Validate and write store.json; sign it (store.json.sig) when a key is given."""
    store = out / "store.json"
    _dump(store, doc, schema="store")
    sig = sshsig.sign(store, key, SNAPSHOT_NAMESPACE) if key else None
    return store, sig
