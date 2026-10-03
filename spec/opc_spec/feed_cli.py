"""opc-feed: a provider's feed directory before and after keyless signing (spec/PROTOCOL.md §3, ADR-0039).

    opc-feed check FEED --provider ID     validate every statements/<id>/<commit>.json; print the
                                          ones without a bundle (to sign), one per line; exit 1 on
                                          any invalid statement or a bundle that carries another one
    opc-feed index FEED --provider ID     every statement must have a matching bundle; write the
                                          index.json to sign (version above the previous index's)

FEED is the `feed/v1` directory. The index is rebuilt from the statements on disk, so an
`index.json` committed by anyone else is replaced, never signed as it is.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
from pathlib import Path

from opc_spec import feed, vocab
from opc_spec.jsonv import integer


def _statements(root: Path) -> list[str]:
    return sorted(
        p.relative_to(root).as_posix()
        for p in (root / "statements").glob("*/*.json")
        if not p.name.endswith(feed.BUNDLE_SUFFIX)
    )


def _scan(args: argparse.Namespace) -> tuple[list[str], list[str]]:
    """(problems, statements without a bundle) for the feed directory."""
    root = Path(args.feed)
    errs: list[str] = []
    pending: list[str] = []
    for rel in _statements(root):
        data = (root / rel).read_bytes()
        found = feed.problems(rel, data, provider=args.provider, predicate_type=args.predicate_type)
        errs += found
        bundle = root / feed.bundle_path(rel)
        if found:
            continue
        if not bundle.exists():
            pending.append(rel)
        elif not feed.bundle_matches(data, bundle.read_bytes()):
            errs.append(f"{rel}: its bundle carries a different statement (statements are immutable)")
    return errs, pending


def cmd_check(args: argparse.Namespace) -> int:
    """Print statements to sign; 1 if any statement or existing bundle is wrong."""
    errs, pending = _scan(args)
    for e in errs:
        print(e, file=sys.stderr)
    for rel in pending:
        print(rel)
    return 1 if errs else 0


def cmd_index(args: argparse.Namespace) -> int:
    """Write index.json over every signed statement; 1 if anything is unsigned or wrong."""
    errs, pending = _scan(args)
    errs += [f"{rel}: not signed yet" for rel in pending]
    if errs:
        for e in errs:
            print(e, file=sys.stderr)
        return 1
    root = Path(args.feed)
    previous = feed.parse((root / "index.json").read_bytes()) if (root / "index.json").exists() else None
    entries = [
        feed.entry(rel, json.loads((root / rel).read_bytes()), (root / feed.bundle_path(rel)).read_bytes())
        for rel in _statements(root)
    ]
    doc = feed.index(
        entries,
        provider=args.provider,
        predicate_type=args.predicate_type,
        now=dt.datetime.now(dt.UTC),
        previous_version=integer((previous or {}).get("version")) or 0,
        ttl=dt.timedelta(days=args.ttl_days),
    )
    (root / "index.json").write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")
    print(f"index.json: version {doc['version']}, {len(entries)} entries, expires {doc['expires']}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    """Argument parser for opc-feed."""
    p = argparse.ArgumentParser(
        prog="opc-feed", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    sub = p.add_subparsers(dest="command", required=True)
    for name, func in (("check", cmd_check), ("index", cmd_index)):
        c = sub.add_parser(name)
        c.add_argument("feed", help="the feed/v1 directory")
        c.add_argument("--provider", required=True, help="registry provider id")
        c.add_argument("--predicate-type", default=vocab.predicate_type())
        if name == "index":
            c.add_argument("--ttl-days", type=int, default=30, help="index lifetime (at most 30)")
        c.set_defaults(func=func)
    return p


def main(argv: list[str] | None = None) -> int:
    """Entry point."""
    args = build_parser().parse_args(argv)
    return int(args.func(args))
