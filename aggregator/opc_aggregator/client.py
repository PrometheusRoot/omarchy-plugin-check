"""The store app's client bundle (ADR-0032), projected from a store.json document. Pure.

`store-home.json` is what the first frame shows (shelves + only the rows they reference),
`store-search.json` is every plugin as parallel arrays with repeated strings interned, and
`store-details.json` maps plugin ids to the sha256 of their detail documents. One signed
`store-manifest.json` commits to all of them (TUF-style snapshot metadata: one signature, hashes
for the rest). store.json stays the CLI's contract; the bundle is a lossless-enough projection
for the store app, never a second source of truth.
"""

from __future__ import annotations

import hashlib
from typing import TYPE_CHECKING, Any, Final

from opc_spec.jsonv import obj, objs, strs, text
from opc_spec.vocab import (
    CRITERIA,
    DETAILS_KIND,
    HOME_KIND,
    MANIFEST_KIND,
    SEARCH_KIND,
    VERDICTS,
)

if TYPE_CHECKING:
    from collections.abc import Iterable, Mapping, Sequence

SHELF_MAX: Final = 12
"""Ids per shelf in the home slice (what the UI shows; ranking never shelves blocked plugins)."""
HOME_DROP: Final = ("gallery",)
"""Row keys the home slice leaves to the detail document (listing)."""
DESC_MAX: Final = 200
VERDICT_ORDER: Final = (*VERDICTS, "unknown")
BASIS_ORDER: Final = ("trusted", "untrusted", "none")
GITHUB: Final = "https://github.com/"
HOME_KEYS: Final = (
    "generatedAt",
    "expires",
    "dev",
    "catalog",
    "imageBase",
    "apiBase",
    "providers",
    "ranking",
    "categories",
)
FLAG_CONTESTED, FLAG_ARCHIVED, FLAG_NO_INSTALL, FLAG_CUSTOM_INSTALL = 1, 2, 4, 8
FLAG_RETIRED, FLAG_BUILTIN, FLAG_DETAIL = 16, 32, 64


def _ids(value: object, limit: int) -> list[str]:
    return strs(value)[:limit]


def home_doc(store: Mapping[str, Any]) -> dict[str, Any]:
    """store-home.json: envelope, counts, shelves cut to SHELF_MAX and exactly the rows they use (sans HOME_DROP)."""
    sh = obj(store.get("shelves"))
    shelves: dict[str, Any] = {
        k: _ids(sh.get(k), SHELF_MAX) for k in ("top", "trending", "new", "updated", "safePicks")
    }
    shelves["byCategory"] = {c: _ids(v, SHELF_MAX) for c, v in obj(sh.get("byCategory")).items()}
    wanted = {i for k, v in shelves.items() if k != "byCategory" for i in v}
    wanted |= {i for v in shelves["byCategory"].values() for i in v}
    plugins = objs(store.get("plugins"))
    counts = dict.fromkeys([*VERDICT_ORDER, "images"], 0)
    for p in plugins:
        v = text(obj(p.get("verdict")).get("combined")) or "unknown"
        counts[v if v in counts else "unknown"] += 1
        counts["images"] += 1 if obj(p.get("img")).get("thumb") else 0
    return (
        {"schemaVersion": 1, "kind": HOME_KIND, "version": store["version"]}
        | {k: store[k] for k in HOME_KEYS}
        | {
            "counts": counts,
            "total": len(plugins),
            "shelves": shelves,
            "plugins": [
                {k: v for k, v in p.items() if k not in HOME_DROP} for p in plugins if p.get("id") in wanted
            ],
        }
    )


class _Interner:
    """Strings → stable small indices (first-seen order)."""

    def __init__(self) -> None:
        self.index: dict[str, int] = {}

    def __call__(self, value: object) -> int:
        s = text(value)
        if not s:
            return -1
        return self.index.setdefault(s, len(self.index))

    def values(self) -> list[str]:
        return list(self.index)


def short_desc(desc: str, limit: int = DESC_MAX) -> str:
    """`desc` cut at a word boundary to at most `limit` characters (with an ellipsis if cut)."""
    desc = " ".join(desc.split())
    if len(desc) <= limit:
        return desc
    cut = desc[: limit - 1]
    space = cut.rfind(" ")
    return (cut[:space] if space > limit // 2 else cut).rstrip(" ,.;:-") + "…"


def short_repo(repo: str) -> str:
    """'owner/name' for a GitHub URL, else the URL itself."""
    return repo.removeprefix(GITHUB) if repo.startswith(GITHUB) else repo


def _mask(names: Iterable[str]) -> int:
    return sum(1 << CRITERIA.index(n) for n in set(names) if n in CRITERIA)


def _flags(p: Mapping[str, Any], *, has_detail: bool) -> int:
    v, gh = obj(p.get("verdict")), obj(p.get("gh"))
    install = p.get("install")
    bits = FLAG_CONTESTED if v.get("contested") else 0
    bits |= FLAG_ARCHIVED if gh.get("archived") else 0
    bits |= FLAG_NO_INSTALL if install == "" else 0
    bits |= FLAG_CUSTOM_INSTALL if isinstance(install, str) and install else 0
    bits |= FLAG_RETIRED if p.get("state") == "retired" else 0
    bits |= FLAG_BUILTIN if p.get("state") == "builtin" else 0
    return bits | (FLAG_DETAIL if has_detail else 0)


COLUMNS: Final = (
    "id", "name", "author", "tags", "desc", "cat", "kind", "verif", "verdict", "basis", "flags", "rank",
    "score", "stars", "vel30", "listed", "updated", "thumb", "repo", "commit", "risk", "critC", "critF",
    "ini", "accent",
)  # fmt: skip


def search_doc(store: Mapping[str, Any], detail_ids: Iterable[str] | None = None) -> dict[str, Any]:
    """store-search.json: every store.json row as parallel arrays (row order = store.json order).

    `detail_ids`: plugins that have a detail document (default: those whose row says `report`).
    """
    plugins = objs(store.get("plugins"))
    with_detail = set(detail_ids) if detail_ids is not None else {p["id"] for p in plugins if p.get("report")}
    cat, kind, author, verif, accent = _Interner(), _Interner(), _Interner(), _Interner(), _Interner()
    providers = [str(p["id"]) for p in objs(store.get("providers"))]
    cols: dict[str, list[Any]] = {k: [] for k in COLUMNS}
    prov: list[list[int]] = [[] for _ in providers]
    for p in plugins:
        v, gh, img = obj(p.get("verdict")), obj(p.get("gh")), obj(p.get("img"))
        crit = obj(v.get("criteria"))
        combined = text(v.get("combined")) or "unknown"
        basis = text(v.get("basis")) or "none"
        row: dict[str, Any] = {
            "id": p["id"],
            "name": p["name"],
            "author": author(p.get("author")),
            "tags": " ".join(strs(p.get("tags"))),
            "desc": short_desc(text(p.get("desc")) or ""),
            "cat": cat(p.get("cat")),
            "kind": kind(p.get("kind")),
            "verif": verif(p.get("verif")),
            "verdict": VERDICT_ORDER.index(combined) if combined in VERDICT_ORDER else 4,
            "basis": BASIS_ORDER.index(basis) if basis in BASIS_ORDER else 2,
            "flags": _flags(p, has_detail=p["id"] in with_detail),
            "rank": p.get("rank"),
            "score": p.get("score"),
            "stars": gh.get("stars") or 0,
            "vel30": gh.get("vel30"),
            "listed": (text(p.get("listed")) or "")[:10],
            "updated": (text(p.get("updated")) or text(gh.get("lastCommit")) or "")[:10],
            "thumb": text(img.get("thumb")) or "",
            "repo": short_repo(text(p.get("repo")) or ""),
            "commit": text(v.get("commit")) or "",
            "risk": v.get("risk"),
            "critC": _mask(strs(crit.get("checked"))),
            "critF": _mask(strs(crit.get("failed"))),
            "ini": text(p.get("ini")) or "",
            "accent": accent(p.get("accent")),
        }
        for k in COLUMNS:
            cols[k].append(row[k])
        pv = obj(v.get("providers"))
        for i, pid in enumerate(providers):
            got = text(pv.get(pid))
            prov[i].append(VERDICT_ORDER.index(got) if got in VERDICT_ORDER else -1)
    return {
        "schemaVersion": 1,
        "kind": SEARCH_KIND,
        "version": store["version"],
        "n": len(plugins),
        "dict": {
            "cat": cat.values(),
            "kind": kind.values(),
            "author": author.values(),
            "verif": verif.values(),
            "accent": accent.values(),
            "verdict": list(VERDICT_ORDER),
            "basis": list(BASIS_ORDER),
            "providers": providers,
            "criteria": list(CRITERIA),
        },
        "cols": cols | {"prov": prov},
    }


def details_doc(version: int, hashes: Mapping[str, str]) -> dict[str, Any]:
    """store-details.json: plugin id → sha256 of its detail document."""
    return {
        "schemaVersion": 1,
        "kind": DETAILS_KIND,
        "version": version,
        "docs": dict(sorted(hashes.items())),
    }


def manifest_doc(store: Mapping[str, Any], files: Sequence[tuple[str, str, bytes]]) -> dict[str, Any]:
    """store-manifest.json for [(role, path, exact bytes)]; version/expiry/dev from store.json."""
    return {
        "schemaVersion": 1,
        "kind": MANIFEST_KIND,
        "version": store["version"],
        "generatedAt": store["generatedAt"],
        "expires": store["expires"],
        "dev": store["dev"],
        "files": [
            {"role": role, "path": path, "sha256": hashlib.sha256(data).hexdigest(), "size": len(data)}
            for role, path, data in files
        ],
    }
