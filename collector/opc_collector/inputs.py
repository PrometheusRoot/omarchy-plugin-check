"""Join marketplace, GitHub stats, engagement and aggregated verdicts into collector inputs. Pure."""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from opc_spec import ids
from opc_spec.jsonv import integer, obj, objs, text
from opc_spec.marketplace import Marketplace, manifest_dir

from opc_collector.query import RepoRef
from opc_collector.rank import Item
from opc_collector.stats import parse_time

if TYPE_CHECKING:
    import datetime as dt
    from collections.abc import Iterable, Mapping


def repo_refs(market: Marketplace) -> list[RepoRef]:
    """One RepoRef per GitHub repository of a listed plugin, with its plugin directories."""
    dirs: dict[str, set[str]] = {}
    names: dict[str, tuple[str, str]] = {}
    for p in market.plugins.values():
        gh = ids.github_repo(p.repo or "")
        if p.state != "listed" or gh is None or not p.repo_key:
            continue
        names.setdefault(p.repo_key, gh)
        d = manifest_dir(p.raw)
        dirs.setdefault(p.repo_key, set()).update({d} if d else set())
    return [RepoRef(k, *names[k], tuple(sorted(dirs[k]))) for k in sorted(names)]


def seeds(catalogs: Iterable[Mapping[str, Any]]) -> dict[str, list[tuple[dt.date, int]]]:
    """Star-count points per repo key from marketplace catalogs (`stars` at catalog `generatedAt`)."""
    out: dict[str, dict[dt.date, int]] = {}
    for cat in catalogs:
        at = parse_time(cat.get("generatedAt"))
        if at is None:
            continue
        for p in objs(cat.get("plugins")):
            key = ids.repo_key(text(p.get("repo")) or "")
            stars = integer(p.get("stars"))
            if key and stars is not None:
                day = out.setdefault(key, {})
                day[at.date()] = max(day.get(at.date(), 0), stars)
    return {k: sorted(v.items()) for k, v in out.items()}


def items(
    market: Marketplace,
    repos: Mapping[str, Mapping[str, Any]],
    engagement: Mapping[str, Mapping[str, Any]],
    index: Mapping[str, Any] | None,
) -> list[Item]:
    """Ranking Items for every catalog plugin."""
    verdicts = {text(r.get("id")): r for r in objs(obj(index).get("plugins"))}
    out: list[Item] = []
    for p in sorted(market.plugins.values(), key=lambda p: p.id):
        st = obj(repos.get(p.repo_key or ""))
        v = obj(verdicts.get(p.id))
        out.append(
            Item(
                id=p.id,
                state=p.state,
                category=text(p.raw.get("category")),
                stars=integer(st.get("stars")) or integer(p.raw.get("stars")) or 0,
                vel30=integer(st.get("vel30")) or 0,
                last_commit=parse_time(st.get("lastCommit")),
                c90=integer(st.get("c90")),
                contrib=integer(st.get("contrib")),
                rel180=integer(st.get("rel180")),
                resp_h=st.get("respH") if isinstance(st.get("respH"), (int, float)) else None,
                views=integer(obj(engagement.get(p.id)).get("views")) or 0,
                verified=p.raw.get("verificationStatus") == "verified",
                quality=integer(v.get("quality")),
                verdict=text(v.get("verdict")) or "unknown",
                trusted=v.get("basis") == "trusted",
                listed_at=text(p.raw.get("listedAt")),
                updated_at=text(p.raw.get("repositoryUpdatedAt")),
            )
        )
    return out
