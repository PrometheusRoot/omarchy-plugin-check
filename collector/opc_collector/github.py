"""Batch-fetch GitHub stats for catalog repositories: resumable, cached, inside the rate limit.

Imperative shell over `query` + `stats`. Each repository's result is cached as one JSON file
(`<cache>/github/<owner>__<name>.json`, with its star-count history); a rerun skips fresh entries,
so an interrupted or rate-limited run resumes where it stopped.
"""

from __future__ import annotations

import datetime as dt
import json
import time
from dataclasses import dataclass, field
from typing import TYPE_CHECKING, Any, Final

from opc_spec.jsonv import arr, integer, obj, text

from opc_collector import query, stats
from opc_collector.ports import RateLimitedError, TransientError

if TYPE_CHECKING:
    from collections.abc import Callable, Mapping, Sequence
    from pathlib import Path

    from opc_collector.ports import GraphQL

COMMITS_WINDOW: Final = dt.timedelta(days=90)
DEFAULT_TTL: Final = dt.timedelta(hours=20)
RESERVE_POINTS: Final = 100
"""Stop (or wait for the reset) when fewer points than this remain."""


@dataclass
class Report:
    """What one collection run did (printed by the CLI, kept in stats.json)."""

    requested: int = 0
    fresh: int = 0
    fetched: int = 0
    missing: int = 0
    failed: int = 0
    queries: int = 0
    points: int = 0
    remaining: int | None = None
    reset_at: str | None = None
    seconds: float = 0.0
    stopped: str | None = None
    errors: list[str] = field(default_factory=list[str])


@dataclass(frozen=True)
class Options:
    """Run knobs; defaults suit a nightly run."""

    batch_size: int = 12
    ttl: dt.timedelta = DEFAULT_TTL
    max_wait: float = 900.0
    pause: float = 1.0
    max_repos: int | None = None


class Cache:
    """One JSON file per repository below `<root>/github/`."""

    def __init__(self, root: Path) -> None:
        """Create the cache directory lazily under `root`."""
        self.dir = root / "github"

    def path(self, ref: query.RepoRef) -> Path:
        """Cache file of a repository."""
        return self.dir / f"{ref.owner.lower()}__{ref.name.lower()}.json"

    def load(self, ref: query.RepoRef) -> dict[str, Any] | None:
        """The cached record, or None."""
        p = self.path(ref)
        if not p.is_file():
            return None
        try:
            return obj(json.loads(p.read_text(encoding="utf-8")))
        except ValueError:
            return None

    def save(self, ref: query.RepoRef, record: Mapping[str, Any]) -> None:
        """Write a record atomically."""
        self.dir.mkdir(parents=True, exist_ok=True)
        p = self.path(ref)
        tmp = p.with_suffix(".tmp")
        tmp.write_text(json.dumps(record, separators=(",", ":")), encoding="utf-8")
        tmp.replace(p)


def _fresh(record: Mapping[str, Any] | None, now: dt.datetime, ttl: dt.timedelta) -> bool:
    fetched = stats.parse_time(obj(record).get("fetchedAt"))
    return fetched is not None and now - fetched < ttl


def _not_found(errors: Sequence[Mapping[str, Any]]) -> set[str]:
    return {str(arr(e.get("path"))[0]) for e in errors if e.get("type") == "NOT_FOUND" and arr(e.get("path"))}


def _record(
    ref: query.RepoRef, node: Mapping[str, Any], prev: Mapping[str, Any] | None, now: dt.datetime
) -> dict[str, Any]:
    st = stats.repo_stats(node, now, owner=ref.owner, name=ref.name, dirs=query.readme_dirs(ref))
    history = stats.add_history(arr(obj(prev).get("history")), now.date(), st["stars"])
    return {"fetchedAt": now.isoformat(), "key": ref.key, "stats": st, "history": history}


class Collector:
    """Runs batches against a GraphQL port; time and sleep are injectable for tests."""

    def __init__(  # noqa: PLR0913  # why: ports and clocks are injected explicitly
        self,
        client: GraphQL,
        cache: Cache,
        opts: Options,
        *,
        now: Callable[[], dt.datetime] = lambda: dt.datetime.now(dt.UTC),
        sleep: Callable[[float], None] = time.sleep,
        log: Callable[[str], None] = lambda _msg: None,
    ) -> None:
        """Bind the ports."""
        self.client, self.cache, self.opts = client, cache, opts
        self.now, self.sleep, self.log = now, sleep, log

    def run(
        self, refs: Sequence[query.RepoRef], seeds: Mapping[str, Sequence[tuple[dt.date, int]]]
    ) -> Report:
        """Fetch every stale repository; `seeds` gives first star-count points per repo key (no cache yet)."""
        started = time.monotonic()
        rep = Report(requested=len(refs))
        now = self.now()
        todo: list[query.RepoRef] = []
        for ref in refs:
            if _fresh(self.cache.load(ref), now, self.opts.ttl):
                rep.fresh += 1
            elif ref.valid():
                todo.append(ref)
            else:
                rep.failed += 1
                rep.errors.append(f"{ref.key}: unsafe owner/name")
        if self.opts.max_repos is not None:
            todo = todo[: self.opts.max_repos]
        self._loop(todo, seeds, rep)
        rep.seconds = round(time.monotonic() - started, 1)
        return rep

    def _loop(
        self, todo: list[query.RepoRef], seeds: Mapping[str, Sequence[tuple[dt.date, int]]], rep: Report
    ) -> None:
        i, size = 0, self.opts.batch_size
        while i < len(todo):
            batch = todo[i : i + size]
            now = self.now()
            try:
                doc = self.client.query(query.batch_query(batch, now - COMMITS_WINDOW))
            except RateLimitedError as exc:
                if exc.retry_after > self.opts.max_wait:
                    rep.stopped = f"rate limited for {exc.retry_after:.0f}s; resume later"
                    return
                self.log(f"rate limited; sleeping {exc.retry_after:.0f}s")
                self.sleep(exc.retry_after)
                continue
            except TransientError as exc:
                size = self._shrink(size, batch, rep, str(exc))
                i += 0 if size else len(batch)
                size = size or 1
                continue
            rep.queries += 1
            if not self._store(batch, doc, seeds, now, rep):
                size = self._shrink(size, batch, rep, "query failed")
                i += 0 if size else len(batch)
                size = size or 1
                continue
            i += len(batch)
            size = min(self.opts.batch_size, size * 2)
            if not self._budget(obj(obj(doc.get("data")).get("rateLimit")), rep):
                return
            self.sleep(self.opts.pause)

    def _shrink(self, size: int, batch: Sequence[query.RepoRef], rep: Report, why: str) -> int:
        """Halve the batch; a single repository that keeps failing is recorded and skipped (returns 0)."""
        if size > 1:
            self.log(f"{why}; batch {size} -> {size // 2}")
            return size // 2
        rep.failed += 1
        rep.errors.append(f"{batch[0].key}: {why}"[:200])
        return 0

    def _store(
        self,
        batch: Sequence[query.RepoRef],
        doc: Mapping[str, Any],
        seeds: Mapping[str, Sequence[tuple[dt.date, int]]],
        now: dt.datetime,
        rep: Report,
    ) -> bool:
        data = obj(doc.get("data"))
        errors = [obj(e) for e in arr(doc.get("errors"))]
        if not data:
            return False
        missing = _not_found(errors)
        for j, ref in enumerate(batch):
            alias = f"r{j}"
            node = obj(data.get(alias))
            prev = self.cache.load(ref)
            if prev is None and ref.key in seeds:
                prev = {"history": [[day.isoformat(), stars] for day, stars in seeds[ref.key]]}
            if node:
                self.cache.save(ref, _record(ref, node, prev, now))
                rep.fetched += 1
            elif alias in missing:
                self.cache.save(ref, {"fetchedAt": now.isoformat(), "key": ref.key, "missing": True})
                rep.missing += 1
            else:
                rep.failed += 1
                rep.errors.append(f"{ref.key}: no data")
        return True

    def _budget(self, rate: Mapping[str, Any], rep: Report) -> bool:
        cost, remaining = integer(rate.get("cost")), integer(rate.get("remaining"))
        rep.points += cost or 0
        rep.remaining, rep.reset_at = remaining, text(rate.get("resetAt"))
        if remaining is None or remaining >= RESERVE_POINTS:
            return True
        reset = stats.parse_time(rep.reset_at)
        wait = max(0.0, (reset - self.now()).total_seconds()) + 5 if reset else self.opts.max_wait + 1
        if wait > self.opts.max_wait:
            rep.stopped = f"{remaining} points left until {rep.reset_at}; resume later"
            return False
        self.log(f"{remaining} points left; sleeping {wait:.0f}s until reset")
        self.sleep(wait)
        return True


def stats_repos(refs: Sequence[query.RepoRef], cache: Cache, today: dt.date) -> dict[str, dict[str, Any]]:
    """Per-repo stats for stats.json from the cache, with star velocity from the history."""
    out: dict[str, dict[str, Any]] = {}
    for ref in refs:
        rec = cache.load(ref)
        st = obj(obj(rec).get("stats"))
        if not st:
            continue
        vel, span = stats.velocity(arr(obj(rec).get("history")), integer(st.get("stars")) or 0, today)
        out[ref.key] = {**st, "vel30": vel, "velDays": span, "fetchedAt": text(obj(rec).get("fetchedAt"))}
    return out
