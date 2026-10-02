"""opc-aggregate: build the static API + signed store snapshot; dev key and verification helpers."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
from pathlib import Path
from typing import TYPE_CHECKING, Any

from opc_spec.vocab import REGISTRY_NAMESPACE, SNAPSHOT_NAMESPACE

from opc_aggregator import build, publish, snapshot, sshsig, state
from opc_aggregator.fetch import HttpsFetcher, LocalFetcher, RoutingFetcher
from opc_aggregator.model import parse_time
from opc_aggregator.sigstore_verifier import SigstoreVerifier
from opc_aggregator.unsigned import UnsignedDevVerifier

if TYPE_CHECKING:
    from opc_aggregator.ports import Verifier

CONFIG = Path.home() / ".config" / "omarchy-plugin-check"
DEV_KEY = CONFIG / "dev-snapshot-key"
STATE = Path.home() / ".cache" / "omarchy-plugin-check" / "aggregator-state.json"
SNAPSHOT_TTL = dt.timedelta(days=7)


def _json(path: str | Path) -> Any:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def _verifiers(*, offline: bool) -> dict[str, Verifier]:
    return {"sigstore": SigstoreVerifier(offline=offline), "none": UnsignedDevVerifier()}


def _registry_signed(args: argparse.Namespace) -> bool:
    if not args.providers_sig:
        return False
    data = Path(args.providers).read_bytes()
    if not sshsig.verify(data, Path(args.providers_sig), Path(args.allowed_signers), REGISTRY_NAMESPACE):
        raise build.RegistryError("providers.json signature does not verify")
    return True


def cmd_build(args: argparse.Namespace) -> int:
    """Aggregate feeds → api/v1/; with --stats/--ranking also store.json (+ .sig with --sign-key)."""
    now = dt.datetime.now(dt.UTC).replace(microsecond=0)
    st_path = Path(args.state)
    st = state.load(st_path)
    reg_doc = _json(args.providers)
    signed = _registry_signed(args)
    if not signed and not reg_doc.get("dev"):
        print("refusing an unsigned registry that is not a dev registry", file=sys.stderr)
        return 2
    base = Path(args.providers).resolve().parent
    inp = build.Inputs(
        registry_doc=reg_doc,
        catalog=_json(args.catalog),
        market_registry=_json(args.registry) if args.registry else None,
        now=now,
        base_dir=base,
    )
    local = LocalFetcher(base) if reg_doc.get("dev") else None
    agg = build.aggregate(inp, RoutingFetcher(HttpsFetcher(), local), _verifiers(offline=args.offline), st)
    out = Path(args.out)
    publish.write_api(agg, out / "api" / "v1", now, registry_signed=signed)
    summary: dict[str, Any] = {
        "plugins": len(agg.combined),
        "providers": [p.doc() for p in agg.providers],
        "rejected": len(agg.rejected),
    }
    if args.stats or args.ranking:
        version = max(int(now.timestamp()), (st.snapshot or 0) + 1)
        dev = agg.registry.dev or (
            args.sign_key is not None and Path(args.sign_key).resolve() == DEV_KEY.resolve()
        )
        meta = snapshot.SnapshotMeta(now, version, now + SNAPSHOT_TTL, dev, args.api_base)
        doc = snapshot.assemble(
            meta,
            agg.market,
            agg.rows,
            agg.combined,
            providers=[p.doc() for p in agg.providers],
            stats=_json(args.stats) if args.stats else None,
            ranking=_json(args.ranking) if args.ranking else None,
        )
        store, sig = publish.write_store(doc, out, Path(args.sign_key) if args.sign_key else None)
        st.snapshot = version
        summary |= {"store": str(store), "signature": str(sig) if sig else None, "version": version}
    state.save(st_path, st)
    print(json.dumps(summary, indent=2))
    return 0


def cmd_keygen(args: argparse.Namespace) -> int:
    """Create the DEV snapshot key (outside the repo, mode 600) and print its allowed_signers line."""
    key = Path(args.key)
    if key.exists():
        print(f"{key} exists; not overwriting", file=sys.stderr)
    else:
        sshsig.keygen(key, "omarchy-plugin-check DEV ONLY snapshot key")
    pub = key.with_name(key.name + ".pub").read_text(encoding="utf-8").strip()
    print(pub)
    print(sshsig.allowed_signers_line(pub, namespaces=(SNAPSHOT_NAMESPACE, REGISTRY_NAMESPACE)))
    return 0


def cmd_sign(args: argparse.Namespace) -> int:
    """Sign a file (providers.json or store.json) with a namespace."""
    ns = {"registry": REGISTRY_NAMESPACE, "snapshot": SNAPSHOT_NAMESPACE}[args.purpose]
    print(sshsig.sign(Path(args.file), Path(args.key), ns))
    return 0


def cmd_verify(args: argparse.Namespace) -> int:
    """Verify store.json: signature, then expiry and rollback (exit 1 on any failure)."""
    data = Path(args.store).read_bytes()
    if not sshsig.verify(
        data, Path(args.sig or args.store + ".sig"), Path(args.allowed_signers), SNAPSHOT_NAMESPACE
    ):
        print("signature: BAD", file=sys.stderr)
        return 1
    doc = json.loads(data)
    now = dt.datetime.now(dt.UTC)
    if parse_time(doc["expires"]) <= now:
        print(f"expired at {doc['expires']}", file=sys.stderr)
        return 1
    if args.min_version is not None and int(doc["version"]) < args.min_version:
        print(f"rollback: version {doc['version']} < {args.min_version}", file=sys.stderr)
        return 1
    print(f"ok version={doc['version']} expires={doc['expires']} dev={doc['dev']}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    """Argument parser for opc-aggregate."""
    p = argparse.ArgumentParser(prog="opc-aggregate", description=__doc__)
    sub = p.add_subparsers(dest="command", required=True)
    b = sub.add_parser("build", help="feeds → api/v1 (+ store.json with --stats/--ranking)")
    b.add_argument("--providers", required=True, help="providers.json")
    b.add_argument("--providers-sig", help="providers.json.sig (required unless the registry is dev)")
    b.add_argument("--allowed-signers", default="spec/keys/allowed_signers.dev")
    b.add_argument("--catalog", required=True, help="marketplace catalog.json")
    b.add_argument("--registry", help="marketplace registry.json (baseline source, migrations, retired)")
    b.add_argument("--out", required=True)
    b.add_argument("--stats", help="collector stats.json")
    b.add_argument("--ranking", help="collector ranking.json")
    b.add_argument("--sign-key", help="ed25519 key for store.json.sig")
    b.add_argument("--api-base", default="api/v1/")
    b.add_argument("--state", default=str(STATE))
    b.add_argument(
        "--offline", action="store_true", help="sigstore: use the bundled trust root, no TUF refresh"
    )
    b.set_defaults(func=cmd_build)
    k = sub.add_parser("keygen", help="create the DEV snapshot key")
    k.add_argument("--key", default=str(DEV_KEY))
    k.set_defaults(func=cmd_keygen)
    s = sub.add_parser("sign", help="sign a file with the snapshot or registry namespace")
    s.add_argument("purpose", choices=["registry", "snapshot"])
    s.add_argument("file")
    s.add_argument("--key", default=str(DEV_KEY))
    s.set_defaults(func=cmd_sign)
    v = sub.add_parser("verify-snapshot", help="verify store.json signature, expiry, version")
    v.add_argument("store")
    v.add_argument("--sig")
    v.add_argument("--allowed-signers", default="spec/keys/allowed_signers.dev")
    v.add_argument("--min-version", type=int)
    v.set_defaults(func=cmd_verify)
    return p


def main(argv: list[str] | None = None) -> int:
    """Entry point."""
    args = build_parser().parse_args(argv)
    try:
        return int(args.func(args))
    except (build.RegistryError, publish.PublishError, sshsig.SshSigError) as exc:
        print(f"opc-aggregate: {exc}", file=sys.stderr)
        return 2
