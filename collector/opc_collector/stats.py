"""GraphQL repository node → the per-repo stats the ranking and the store use. Pure.

Every field is defined in docs/RANKING.md; anything missing in the node becomes None (never 0), so
the ranking can tell "no data" from "zero".
"""

from __future__ import annotations

import datetime as dt
import statistics
from itertools import accumulate
from typing import TYPE_CHECKING, Any, Final

from opc_spec.jsonv import integer, obj, objs, text

from opc_collector.readme import image_urls

if TYPE_CHECKING:
    from collections.abc import Mapping, Sequence

RELEASE_WINDOW: Final = dt.timedelta(days=180)
VELOCITY_WINDOW_DAYS: Final = 30
HISTORY_DAYS: Final = 120
README_ALIASES: Final = ("readme0", "readme1", "readme2", "readme3", "readme4")


def parse_time(value: object) -> dt.datetime | None:
    """RFC 3339 string → aware datetime, else None."""
    s = text(value)
    if not s:
        return None
    try:
        t = dt.datetime.fromisoformat(s)
    except ValueError:
        return None
    return t if t.tzinfo else t.replace(tzinfo=dt.UTC)


def authors(commits: Sequence[Mapping[str, Any]]) -> list[str]:
    """Author identity per commit: GitHub login, else lower-cased email, else 'unknown'."""
    out: list[str] = []
    for c in commits:
        a = obj(c.get("author"))
        out.append(text(obj(a.get("user")).get("login")) or (text(a.get("email")) or "unknown").lower())
    return out


def bus_factor(who: Sequence[str]) -> int | None:
    """Fewest authors who together made at least half of the commits (None without commits)."""
    if not who:
        return None
    counts = sorted((who.count(a) for a in set(who)), reverse=True)
    return next(n for n, acc in enumerate(accumulate(counts), 1) if acc * 2 >= len(who))


def first_response_hours(issues: Sequence[Mapping[str, Any]]) -> float | None:
    """Median hours from issue creation to the first comment by someone other than the author."""
    hours: list[float] = []
    for issue in issues:
        opened = parse_time(issue.get("createdAt"))
        author = text(obj(issue.get("author")).get("login"))
        for c in objs(obj(issue.get("comments")).get("nodes")):
            who = text(obj(c.get("author")).get("login"))
            at = parse_time(c.get("createdAt"))
            if opened and at and who and who != author:
                hours.append(max(0.0, (at - opened).total_seconds() / 3600))
                break
    return round(statistics.median(hours), 1) if hours else None


def _readme_text(node: Mapping[str, Any]) -> str | None:
    for alias in README_ALIASES:
        t = text(obj(node.get(alias)).get("text"))
        if t:
            return t
    return None


def repo_stats(
    node: Mapping[str, Any], now: dt.datetime, *, owner: str, name: str, dirs: Sequence[str] = ()
) -> dict[str, Any]:
    """Stats for one repository node (see docs/RANKING.md for every field)."""
    branch = obj(node.get("defaultBranchRef"))
    target = obj(branch.get("target"))
    commits = objs(obj(target.get("recent")).get("nodes"))
    who = authors(commits)
    oid = text(target.get("oid"))
    releases = objs(obj(node.get("releases")).get("nodes"))
    published = [t for t in (parse_time(r.get("publishedAt")) for r in releases) if t]
    readme = _readme_text(node)
    ref = oid or text(branch.get("name")) or "HEAD"
    dir_images: dict[str, list[str]] = {}
    for i, d in enumerate(dirs):
        t = text(obj(node.get(f"dir{i}")).get("text"))
        imgs = image_urls(t, owner, name, ref, d) if t else []
        if imgs:
            dir_images[d] = imgs
    return {
        "stars": integer(node.get("stargazerCount")) or 0,
        "archived": node.get("isArchived") is True,
        "pushedAt": text(node.get("pushedAt")),
        "branch": text(branch.get("name")),
        "head": oid,
        "lastCommit": text(commits[0].get("committedDate")) if commits else None,
        "c90": integer(obj(target.get("h90")).get("totalCount")) if target else None,
        "contrib": len(set(who)) if who else None,
        "bus": bus_factor(who),
        "rel180": sum(1 for t in published if now - t <= RELEASE_WINDOW) if node.get("releases") else None,
        "releases": integer(obj(node.get("releases")).get("totalCount")),
        "lastRelease": text(releases[0].get("tagName")) if releases else None,
        "issues": integer(obj(node.get("openIssues")).get("totalCount")),
        "respH": first_response_hours(objs(obj(node.get("recentIssues")).get("nodes"))),
        "images": image_urls(readme, owner, name, ref) if readme else [],
        "dirImages": dir_images,
    }


def add_history(history: Sequence[Sequence[Any]], day: dt.date, stars: int) -> list[list[Any]]:
    """Star-count history with one point per UTC day (latest wins), the last HISTORY_DAYS kept."""
    points = {str(p[0]): int(p[1]) for p in history if len(p) == 2}
    points[day.isoformat()] = stars
    keep = sorted(points.items())
    cutoff = (day - dt.timedelta(days=HISTORY_DAYS)).isoformat()
    return [[d, s] for d, s in keep if d >= cutoff]


def velocity(history: Sequence[Sequence[Any]], stars: int, today: dt.date) -> tuple[int, int]:
    """(stars gained per 30 days, span in days it is measured over); (0, 0) without a usable point.

    Uses the oldest point at most 30 days old (and at least 1 day old); if every point is older,
    the newest of them, scaled to 30 days. Never negative (unstars count as 0 gain).
    """
    dated = sorted((dt.date.fromisoformat(str(p[0])), int(p[1])) for p in history if len(p) == 2)
    older = [(d, s) for d, s in dated if (today - d).days >= 1]
    if not older:
        return 0, 0
    within = [(d, s) for d, s in older if (today - d).days <= VELOCITY_WINDOW_DAYS]
    day, then = within[0] if within else older[-1]
    span = (today - day).days
    return max(0, round((stars - then) * VELOCITY_WINDOW_DAYS / span)), span
