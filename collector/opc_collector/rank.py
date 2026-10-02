"""Ranking and shelves (docs/RANKING.md). Pure, total, deterministic; property-tested.

rank score = (sum of weight_f * factor_f) * gate(verdict), every factor clamped to [0, 1]. Blocked,
retired and built-in plugins are never ranked and never appear on a shelf.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import TYPE_CHECKING, Final, TypedDict

if TYPE_CHECKING:
    import datetime as dt
    from collections.abc import Callable, Sequence

VERSION: Final = "ranking-v2"
SHELF_SIZE: Final = 50
CATEGORY_SHELF_SIZE: Final = 30
NEUTRAL: Final = 0.5
"""Factor value when the input is unknown for a reason that says nothing about the plugin."""


@dataclass(frozen=True)
class Item:
    """Ranking inputs for one plugin (None = unknown)."""

    id: str
    state: str = "listed"  # listed | retired | builtin
    category: str | None = None
    stars: int = 0
    vel30: int = 0
    last_commit: dt.datetime | None = None
    c90: int | None = None
    contrib: int | None = None
    rel180: int | None = None
    resp_h: float | None = None
    views: int = 0
    verified: bool = False
    verdict: str = "unknown"
    """Combined verdict; only meaningful when `trusted`."""
    trusted: bool = False
    """The combined verdict rests on a core/verified provider (else the plugin counts as unreviewed)."""
    listed_at: str | None = None
    updated_at: str | None = None


def _clamp(x: float) -> float:
    return 0.0 if math.isnan(x) else max(0.0, min(1.0, x))


def _days(now: dt.datetime, t: dt.datetime | None) -> float | None:
    return None if t is None else max(0.0, (now - t).total_seconds() / 86400)


@dataclass(frozen=True)
class Factor:
    """One ranking factor: id, label, weight and its [0, 1] value function."""

    id: str
    label: str
    weight: float
    value: Callable[[Item, dt.datetime], float] = field(compare=False)


def _recency(i: Item, now: dt.datetime) -> float:
    d = _days(now, i.last_commit)
    return 0.0 if d is None else math.exp(-d / 45)


def _issues(i: Item, _now: dt.datetime) -> float:
    if i.resp_h is None:
        return NEUTRAL
    return 1.0 - math.log(max(1.0, i.resp_h)) / math.log(240)


FACTORS: Final[tuple[Factor, ...]] = (
    Factor("stars", "log(stars)", 22, lambda i, _n: math.log10(1 + i.stars) / math.log10(2100)),
    Factor("velocity", "★ velocity 30d", 16, lambda i, _n: math.log(1 + i.vel30) / math.log(401)),
    Factor("recency", "commit recency", 11, _recency),
    Factor("commits", "commits 90d", 11, lambda i, _n: (i.c90 or 0) / 60),
    Factor("contrib", "contributors", 8, lambda i, _n: ((i.contrib or 1) - 1) / 5),
    Factor("releases", "release cadence", 8, lambda i, _n: (i.rel180 or 0) / 4),
    Factor("issues", "issue response", 8, _issues),
    Factor("engage", "marketplace engagement", 11, lambda i, _n: math.log(1 + i.views) / math.log(100001)),
    Factor("verif", "marketplace verification", 5, lambda i, _n: 1.0 if i.verified else 0.3),
    # why: no factor or gate rewards OUR review status - we publish this ranking and also run a
    # provider, so review coverage must not move plugins up (conflict of interest, ADR-0030).
)
GATES: Final[dict[str, float]] = {
    "safe": 1.0,
    "caution": 1.0,
    "unreviewed": 1.0,
    "risky": 0.6,
    "blocked": 0.0,
}
MAX_SCORE: Final = sum(f.weight for f in FACTORS)


def gate_state(item: Item) -> str:
    """Safe | caution | risky | blocked from a trusted combined verdict, else `unreviewed`."""
    if item.trusted and item.verdict in GATES:
        return item.verdict
    return "unreviewed"


def contributions(item: Item, now: dt.datetime) -> list[float]:
    """Weighted factor contributions in FACTORS order (each in [0, weight])."""
    return [f.weight * _clamp(f.value(item, now)) for f in FACTORS]


def eligible(item: Item) -> bool:
    """Ranked and shelf-eligible: listed and not blocked."""
    return item.state == "listed" and gate_state(item) != "blocked"


class Shelves(TypedDict):
    """Shelf id lists (store.json `shelves`)."""

    top: list[str]
    trending: list[str]
    new: list[str]
    updated: list[str]
    safePicks: list[str]
    byCategory: dict[str, list[str]]


@dataclass(frozen=True)
class Ranked:
    """One ranked plugin."""

    id: str
    rank: int
    score: float
    fac: tuple[float, ...]


def rank(items: Sequence[Item], now: dt.datetime) -> list[Ranked]:
    """Eligible items ordered by gated score (ties: more stars, then id); ranks 1..n."""
    scored: list[tuple[float, int, str, tuple[float, ...]]] = []
    for item in items:
        if not eligible(item):
            continue
        fac = contributions(item, now)
        scored.append((sum(fac) * GATES[gate_state(item)], item.stars, item.id, tuple(fac)))
    scored.sort(key=lambda t: (-t[0], -t[1], t[2]))
    return [
        Ranked(pid, n, round(score, 2), tuple(round(x, 2) for x in fac))
        for n, (score, _stars, pid, fac) in enumerate(scored, 1)
    ]


def shelves(items: Sequence[Item], ranked: Sequence[Ranked]) -> Shelves:
    """Shelf id lists. Only eligible items appear; order within each shelf is documented in RANKING.md."""
    by_id = {i.id: i for i in items}
    order = [r.id for r in ranked if r.id in by_id]
    pos = {pid: n for n, pid in enumerate(order)}
    pool = [by_id[pid] for pid in order]
    trending = sorted((i for i in pool if i.vel30 > 0), key=lambda i: (-i.vel30, pos[i.id]))
    new = sorted(
        (i for i in pool if i.listed_at), key=lambda i: (i.listed_at or "", -pos[i.id]), reverse=True
    )
    updated = sorted(
        (i for i in pool if i.updated_at), key=lambda i: (i.updated_at or "", -pos[i.id]), reverse=True
    )
    safe = [i for i in pool if i.trusted and i.verdict == "safe"]
    by_cat: dict[str, list[str]] = {}
    for i in pool:
        if i.category and len(by_cat.setdefault(i.category, [])) < CATEGORY_SHELF_SIZE:
            by_cat[i.category].append(i.id)
    return {
        "top": order[:SHELF_SIZE],
        "trending": [i.id for i in trending[:SHELF_SIZE]],
        "new": [i.id for i in new[:SHELF_SIZE]],
        "updated": [i.id for i in updated[:SHELF_SIZE]],
        "safePicks": [i.id for i in safe[:SHELF_SIZE]],
        "byCategory": dict(sorted(by_cat.items())),
    }


def factor_table() -> list[dict[str, object]]:
    """[{id, label, weight}] for store.json / RANKING.md."""
    return [{"id": f.id, "label": f.label, "weight": f.weight} for f in FACTORS]
