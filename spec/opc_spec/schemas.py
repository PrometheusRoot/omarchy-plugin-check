"""Load the protocol JSON Schemas (spec/schemas + the report extension in schemas/) and validate documents."""

from __future__ import annotations

import json
from functools import cache
from pathlib import Path
from typing import Any, Final

from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource

SCHEMAS: Final = {
    "statement": "statement.schema.json",
    "predicate": "predicate.schema.json",
    "feed-index": "feed-index.schema.json",
    "providers": "providers.schema.json",
    "store": "store.schema.json",
    "store-manifest": "store-manifest.schema.json",
    "store-home": "store-home.schema.json",
    "store-search": "store-search.schema.json",
    "store-details": "store-details.schema.json",
    "api-plugin": "api-plugin.schema.json",
    "api-index": "api-index.schema.json",
    "api-meta": "api-meta.schema.json",
    "api-by-repo": "api-by-repo.schema.json",
    "common": "common.schema.json",
}
_HERE: Final = Path(__file__).resolve().parent


def _dirs(here: Path = _HERE) -> tuple[Path, Path]:
    """(spec schemas, report-extension schemas): the wheel copy if present, else the repo checkout."""
    if (here / "_schemas").is_dir():
        return here / "_schemas", here / "_report_schemas"
    root = here.parents[1]
    return root / "spec" / "schemas", root / "schemas"


@cache
def _load() -> tuple[Registry[Any], dict[str, dict[str, Any]]]:
    spec_dir, ext_dir = _dirs()
    registry: Registry[Any] = Registry()
    docs: dict[str, dict[str, Any]] = {}
    for name, filename in SCHEMAS.items():
        doc: dict[str, Any] = json.loads((spec_dir / filename).read_text(encoding="utf-8"))
        docs[name] = doc
        registry = registry.with_resource(doc["$id"], Resource.from_contents(doc))
    for path in sorted(ext_dir.glob("*.schema.json")):  # the report extension and what it references
        ext: dict[str, Any] = json.loads(path.read_text(encoding="utf-8"))
        registry = registry.with_resource(ext["$id"], Resource.from_contents(ext))
    return registry.crawl(), docs


def schema(name: str) -> dict[str, Any]:
    """The parsed schema document for `name` (a key of SCHEMAS)."""
    return _load()[1][name]


def errors(instance: object, name: str) -> list[str]:
    """Human-readable validation errors sorted by location; empty means valid."""
    registry, docs = _load()
    v: Any = Draft202012Validator(  # why: iter_errors overloads are partially untyped in jsonschema
        docs[name], registry=registry, format_checker=FormatChecker()
    )
    out: list[str] = []
    for err in sorted(v.iter_errors(instance), key=lambda e: [str(p) for p in e.absolute_path]):
        loc = "/".join(str(p) for p in err.absolute_path) or "<root>"
        out.append(f"{loc}: {err.message}")
    return out


def check(instance: object, name: str) -> None:
    """Raise ValueError listing the first errors if `instance` does not validate against `name`."""
    errs = errors(instance, name)
    if errs:
        raise ValueError(f"{name}: " + "; ".join(errs[:5]))
