"""Marketplace identity: catalog.json + registry.json → plugins, states, repository migrations.

The marketplace (plugins.omarchy.org catalog + omacom/omarchy-plugin-marketplace registry) is the
only source of plugin identity (ADR-0010): ids, names, repositories, retirements, migrations and
built-ins come from here. Pure: takes the parsed documents; malformed entries are skipped.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import TYPE_CHECKING, Any, Literal

from opc_spec import ids
from opc_spec.jsonv import arr, obj, objs, strs, text

if TYPE_CHECKING:
    from collections.abc import Mapping

State = Literal["listed", "retired", "builtin"]


@dataclass(frozen=True)
class Plugin:
    """One catalog entry: identity plus the verbatim catalog record."""

    id: str
    name: str
    repo: str | None
    repo_key: str | None
    state: State
    raw: Mapping[str, Any]


@dataclass
class Marketplace:
    """The plugin universe with repository migrations (old key → new key)."""

    generated_at: str | None
    plugins: dict[str, Plugin]
    migrations: dict[str, str] = field(default_factory=dict[str, str])

    def canonical(self, key: str) -> str:
        """Follow repositoryMigrations from `key` to the current repository key (cycle-safe)."""
        seen: set[str] = set()
        while key in self.migrations and key not in seen:
            seen.add(key)
            key = self.migrations[key]
        return key

    def by_repo(self) -> dict[str, list[str]]:
        """Repository key (current and previous names) → plugin ids, sorted."""
        out: dict[str, list[str]] = {}
        for p in self.plugins.values():
            if p.repo_key:
                out.setdefault(p.repo_key, []).append(p.id)
        for old in self.migrations:
            new = self.canonical(old)
            if new in out and old not in out:
                out[old] = list(out[new])
        return {k: sorted(v) for k, v in sorted(out.items())}


def _state(raw: Mapping[str, Any], retired: frozenset[str]) -> State:
    if raw["id"] in retired:
        return "retired"
    if raw.get("builtIn") or raw.get("sourceType") == "builtin":
        return "builtin"
    return "listed"


def parse(catalog: Mapping[str, Any], registry: Mapping[str, Any] | None) -> Marketplace:
    """catalog.json (+ registry.json) → Marketplace. Entries without a string id are skipped."""
    reg = obj(registry)
    retired = frozenset(strs(reg.get("retiredPluginIds")))
    plugins: dict[str, Plugin] = {}
    for raw in objs(catalog.get("plugins")):
        pid = text(raw.get("id"))
        if pid is None or not ids.PLUGIN_ID.match(pid):
            continue
        repo_url = text(raw.get("repo"))
        repo = ids.https_url(repo_url) if repo_url else None
        plugins[pid] = Plugin(
            id=pid,
            name=str(raw.get("name") or pid),
            repo=repo,
            repo_key=ids.repo_key(repo) if repo else None,
            state=_state(raw, retired),
            raw=raw,
        )
    market = Marketplace(generated_at=text(catalog.get("generatedAt")), plugins=plugins)
    for m in objs(reg.get("repositoryMigrations")):
        old, new = key_of(m.get("fromRepository")), key_of(m.get("toRepository"))
        if old and new and old != new:
            market.migrations[old] = new
    for s in objs(reg.get("sources")):
        new = key_of(s.get("repo"))
        for prev in arr(obj(s.get("repositoryIdentity")).get("previousRepositories")):
            old = key_of(prev)
            if old and new and old != new:
                market.migrations.setdefault(old, new)
    return market


def key_of(value: object) -> str | None:
    """'owner/name' or a GitHub URL → repo key (None if neither)."""
    if not isinstance(value, str):
        return None
    return ids.repo_key(value if "github.com" in value else f"https://github.com/{value}")


def manifest_dir(raw: Mapping[str, Any]) -> str:
    """Repo-relative plugin directory from `manifestPath` ('' = repository root)."""
    mp = text(raw.get("manifestPath")) or "manifest.json"
    return mp.rsplit("/", 1)[0] if "/" in mp else ""
