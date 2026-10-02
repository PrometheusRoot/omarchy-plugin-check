"""opc-collect: marketplace sync, GitHub stats (GraphQL, resumable), engagement, ranking."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
from pathlib import Path
from typing import Any

from opc_spec import marketplace

from opc_collector import github, inputs, rank, sync
from opc_collector.net import GhGraphQL, TokenError, UrllibHttp, gh_token
from opc_collector.ports import TransientError

CACHE = Path.home() / ".cache" / "omarchy-plugin-check" / "collector"


def _json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _write(path: Path, doc: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(doc, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")


def _market(cache: Path) -> marketplace.Marketplace:
    mk = cache / "marketplace"
    return marketplace.parse(_json(mk / "catalog.json"), _json(mk / "registry.json"))


def cmd_sync(args: argparse.Namespace) -> int:
    """Download catalog.json + registry.json (conditional GET) and print a summary."""
    http = UrllibHttp()
    mk = Path(args.cache) / "marketplace"
    cat = sync.fetch_cached(http, sync.CATALOG_URL, mk / "catalog.json")
    reg = sync.fetch_cached(http, sync.REGISTRY_URL, mk / "registry.json")
    out = sync.summary(_json(cat.path), _json(reg.path))
    out |= {"catalogDownloaded": cat.downloaded, "registryDownloaded": reg.downloaded}
    print(json.dumps(out, indent=2))
    return 0


def cmd_github(args: argparse.Namespace) -> int:
    """Fetch stats for every listed repository not fetched within --ttl-hours."""
    cache = Path(args.cache)
    market = _market(cache)
    refs = inputs.repo_refs(market)
    catalogs = [_json(cache / "marketplace" / "catalog.json"), *(_json(Path(p)) for p in args.seed_catalog)]
    opts = github.Options(
        batch_size=args.batch,
        ttl=dt.timedelta(hours=args.ttl_hours),
        max_wait=args.max_wait,
        pause=args.pause,
        max_repos=args.max_repos,
    )
    client = GhGraphQL(gh_token())
    coll = github.Collector(client, github.Cache(cache), opts, log=lambda m: print(m, file=sys.stderr))
    rep = coll.run(refs, inputs.seeds(catalogs))
    doc = {**rep.__dict__, "repos": len(refs)}
    _write(cache / "github-report.json", doc)
    print(json.dumps(doc, indent=2))
    return 0 if rep.stopped is None else 3


def cmd_stats(args: argparse.Namespace) -> int:
    """Write stats.json: per-repo GitHub stats (from the cache) + marketplace engagement."""
    cache = Path(args.cache)
    now = dt.datetime.now(dt.UTC).replace(microsecond=0)
    market = _market(cache)
    refs = inputs.repo_refs(market)
    repos = github.stats_repos(refs, github.Cache(cache), now.date())
    engagement: dict[str, dict[str, int]] = {}
    fetched: str | None = None
    if not args.no_engagement:
        try:
            engagement, fetched = sync.engagement(UrllibHttp(), cache, now)
        except (TransientError, ValueError) as exc:
            print(f"engagement skipped: {exc}", file=sys.stderr)
    doc = {
        "schemaVersion": 1,
        "generatedAt": now.isoformat().replace("+00:00", "Z"),
        "catalogGeneratedAt": market.generated_at,
        "repos": repos,
        "engagement": engagement,
        "engagementFetchedAt": fetched,
    }
    _write(Path(args.out), doc)
    print(json.dumps({"repos": len(repos), "of": len(refs), "engagement": len(engagement)}, indent=2))
    return 0


def cmd_rank(args: argparse.Namespace) -> int:
    """Write ranking.json from stats.json + the aggregated api/v1/index.json."""
    now = dt.datetime.now(dt.UTC).replace(microsecond=0)
    market = _market(Path(args.cache))
    st = _json(Path(args.stats))
    index = _json(Path(args.api_index)) if args.api_index else None
    items = inputs.items(market, st.get("repos") or {}, st.get("engagement") or {}, index)
    ranked = rank.rank(items, now)
    doc = {
        "schemaVersion": 1,
        "generatedAt": now.isoformat().replace("+00:00", "Z"),
        "version": rank.VERSION,
        "factors": rank.factor_table(),
        "gates": rank.GATES,
        "plugins": {r.id: {"rank": r.rank, "score": r.score, "fac": list(r.fac)} for r in ranked},
        "shelves": rank.shelves(items, ranked),
    }
    _write(Path(args.out), doc)
    print(json.dumps({"ranked": len(ranked), "of": len(items)}, indent=2))
    return 0


def build_parser() -> argparse.ArgumentParser:
    """Argument parser for opc-collect."""
    p = argparse.ArgumentParser(prog="opc-collect", description=__doc__)
    p.add_argument("--cache", default=str(CACHE))
    sub = p.add_subparsers(dest="command", required=True)
    sub.add_parser("sync", help="download catalog.json + registry.json").set_defaults(func=cmd_sync)
    g = sub.add_parser("github", help="GitHub GraphQL stats for catalog repositories (resumable)")
    g.add_argument("--batch", type=int, default=12)
    g.add_argument("--ttl-hours", type=float, default=20)
    g.add_argument("--max-wait", type=float, default=900, help="longest rate-limit wait before stopping")
    g.add_argument("--pause", type=float, default=1.0, help="seconds between queries")
    g.add_argument("--max-repos", type=int)
    g.add_argument("--seed-catalog", action="append", default=[], help="older catalog.json for star history")
    g.set_defaults(func=cmd_github)
    s = sub.add_parser("stats", help="write stats.json (GitHub stats + engagement)")
    s.add_argument("--out", required=True)
    s.add_argument("--no-engagement", action="store_true")
    s.set_defaults(func=cmd_stats)
    r = sub.add_parser("rank", help="write ranking.json")
    r.add_argument("--stats", required=True)
    r.add_argument("--api-index", help="aggregator api/v1/index.json (verdicts for the safety gates)")
    r.add_argument("--out", required=True)
    r.set_defaults(func=cmd_rank)
    return p


def main(argv: list[str] | None = None) -> int:
    """Entry point."""
    args = build_parser().parse_args(argv)
    try:
        return int(args.func(args))
    except (TokenError, TransientError, FileNotFoundError) as exc:
        print(f"opc-collect: {exc}", file=sys.stderr)
        return 2
