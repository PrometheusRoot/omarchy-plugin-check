import datetime as dt
import json
import shutil
from pathlib import Path

import pytest
from opc_spec import schemas

from opc_aggregator import build, cli, publish, snapshot, sshsig
from opc_aggregator.fetch import HttpsFetcher, LocalFetcher, RoutingFetcher
from opc_aggregator.model import parse_provider
from opc_aggregator.ports import VerificationError, Verified
from opc_aggregator.state import State
from opc_aggregator.unsigned import UnsignedDevVerifier

from .helpers import (
    C1,
    EXAMPLE_FEED,
    T0,
    catalog,
    market_registry,
    marketplace_provider_doc,
    provider_doc,
    registry_doc,
    statement,
    write_feed,
)

needs_ssh = pytest.mark.skipif(shutil.which("ssh-keygen") is None, reason="ssh-keygen missing")
BLOCKING = [
    {
        "category": "exec",
        "severity": "critical",
        "confidence": 1,
        "message": "curl | sh",
        "blocking": True,
        "locations": [{"path": "a.qml", "startLine": 3}],
    }
]


def _run(tmp_path, reg, st=None, verifiers=None, now=T0):
    inp = build.Inputs(
        registry_doc=reg, catalog=catalog(), market_registry=market_registry(), now=now, base_dir=tmp_path
    )
    fetcher = RoutingFetcher(HttpsFetcher(), LocalFetcher(tmp_path))
    return build.aggregate(inp, fetcher, verifiers or {"none": UnsignedDevVerifier()}, st or State())


def test_example_feed_end_to_end(tmp_path):
    shutil.copytree(EXAMPLE_FEED, tmp_path / "provider-feed")
    reg = registry_doc(provider_doc(), marketplace_provider_doc())
    st = State()
    agg = _run(tmp_path, reg, st)
    clock = agg.combined["example.clock"]
    assert (clock.verdict, clock.basis, clock.contested) == ("caution", "trusted", False)
    assert [r.provider for r in agg.rows["example.clock"]] == ["example", "marketplace"]
    assert agg.combined["example.suite-a"].verdict == "caution"  # marketplace needs-fixes, capped
    assert agg.combined["example.suite-a"].basis == "untrusted"
    assert st.feeds == {"example": 1759320000}
    assert st.registry == 5
    assert agg.rejected == []
    out = tmp_path / "out"
    index = publish.write_api(agg, out, T0, registry_signed=False)
    assert {p["id"] for p in index["plugins"]} == {"example.clock", "example.suite-a"}
    doc = json.loads((out / "plugins" / "example.clock.json").read_text())
    assert schemas.errors(doc, "api-plugin") == []
    assert doc["providers"][0]["verification"] == "unsigned-dev"
    assert doc["providers"][1]["effectiveVerdict"] == "safe"
    stmt_path = out / doc["providers"][0]["statement"]
    assert json.loads(stmt_path.read_text())["predicate"]["provider"]["id"] == "example"
    meta = json.loads((out / "meta.json").read_text())
    assert meta["counts"]["caution"] == 2
    assert json.loads((out / "by-repo.json").read_text())["repos"]["example/clock-old"] == ["example.clock"]


def test_rejections_are_reported_not_fatal(tmp_path):
    feed = tmp_path / "f"
    write_feed(
        feed,
        {
            "statements/ok.json": statement(verdict="blocked", findings=BLOCKING),
            "statements/unlisted.json": statement(plugin="nope.x"),
            "statements/wrongrepo.json": statement(
                plugin="example.suite-a", repo="https://github.com/evil/x"
            ),
            "statements/badschema.json": statement(verdict="maybe"),
        },
    )
    idx = json.loads((feed / "feed" / "v1" / "index.json").read_text())
    idx["entries"].append({**idx["entries"][0], "path": "statements/missing.json"})
    idx["entries"].append({**idx["entries"][0], "sha256": "0" * 64})
    (feed / "feed" / "v1" / "index.json").write_text(json.dumps(idx))
    agg = _run(tmp_path, registry_doc(provider_doc(feed="f")))
    reasons = sorted(r["reason"].split(":")[0] for r in agg.rejected)
    assert len(agg.rejected) == 5, agg.rejected
    assert any("unlisted" in r["reason"] for r in agg.rejected)
    assert any("marketplace repository" in r["reason"] for r in agg.rejected)
    assert any("statement invalid" in r["reason"] for r in agg.rejected)
    assert any("sha256" in r["reason"] for r in agg.rejected)
    assert reasons
    assert agg.combined["example.clock"].verdict == "blocked"
    assert agg.providers[0].rows == 1


def test_feed_level_rejections(tmp_path):
    write_feed(tmp_path / "f", {"s/a.json": statement()}, version=3)
    st = State(feeds={"example": 4})
    agg = _run(tmp_path, registry_doc(provider_doc(feed="f")), st)
    assert "rollback" in agg.providers[0].status
    assert agg.rows == {}
    assert st.feeds == {"example": 4}
    write_feed(tmp_path / "g", {"s/a.json": statement()}, provider="someone")
    assert "index is for provider" in _run(tmp_path, registry_doc(provider_doc(feed="g"))).providers[0].status
    (tmp_path / "h" / "feed" / "v1").mkdir(parents=True)
    (tmp_path / "h" / "feed" / "v1" / "index.json").write_text('{"nope": 1}')
    assert "index invalid" in _run(tmp_path, registry_doc(provider_doc(feed="h"))).providers[0].status
    assert "index rejected" in _run(tmp_path, registry_doc(provider_doc(feed="missing"))).providers[0].status


def test_unsigned_provider_needs_dev_registry_and_signed_needs_verifier(tmp_path):
    write_feed(tmp_path / "f", {"s/a.json": statement()})
    agg = _run(tmp_path, registry_doc(provider_doc(feed="f"), dev=False))
    assert agg.providers[0].status == "unsigned provider outside a dev registry"
    agg = _run(tmp_path, registry_doc(provider_doc(feed="f", signing="sigstore")))
    assert agg.providers[0].status == "no verifier"


class _SigFake:
    """Pretends to be sigstore: index needs a bundle; attestation time is configurable."""

    def __init__(self, signed_at, fail=False):
        self.signed_at, self.fail = signed_at, fail

    def verify_blob(self, provider, data, bundle):
        if bundle is None or self.fail:
            raise VerificationError("bad index signature")
        return Verified(data, "sigstore", provider.identity, self.signed_at)

    def verify_attestation(self, provider, data):
        return Verified(data, "sigstore", provider.identity, self.signed_at)


def test_signed_feed_with_windows(tmp_path):
    write_feed(tmp_path / "f", {"s/a.json": statement()})
    (tmp_path / "f" / "feed" / "v1" / "index.json.sigstore.json").write_text("{}")
    window = {"from": "2026-09-30T00:00:00Z", "until": "2026-10-03T00:00:00Z", "reason": "compromise"}
    reg = registry_doc(
        provider_doc(feed="f", signing="sigstore", tier="verified", excludedWindows=[window]), dev=False
    )
    agg = _run(tmp_path, reg, verifiers={"sigstore": _SigFake(T0)})
    assert "excluded window" in agg.rejected[0]["reason"]
    agg = _run(tmp_path, reg, verifiers={"sigstore": _SigFake(T0 + dt.timedelta(days=2))})
    row = agg.rows["example.clock"][0]
    assert (row.verification, row.signer, row.tier) == (
        "sigstore",
        reg["providers"][0]["sigstore"]["certificateIdentity"],
        "verified",
    )
    agg = _run(tmp_path, reg, verifiers={"sigstore": _SigFake(T0, fail=True)})
    assert "bad index signature" in agg.providers[0].status


def test_registry_rejected(tmp_path):
    with pytest.raises(build.RegistryError, match="invalid"):
        _run(tmp_path, {"schemaVersion": 1})
    with pytest.raises(build.RegistryError, match="expired"):
        _run(tmp_path, registry_doc(expires="2026-10-01T00:00:00Z"))
    with pytest.raises(build.RegistryError, match="rollback"):
        _run(tmp_path, registry_doc(), State(registry=9))


def test_baseline_without_marketplace_registry(tmp_path):
    inp = build.Inputs(
        registry_doc=registry_doc(marketplace_provider_doc()), catalog=catalog(), market_registry=None, now=T0
    )
    agg = build.aggregate(inp, RoutingFetcher(HttpsFetcher(), None), {}, State())
    assert agg.providers[0].status == "marketplace registry.json not provided"
    https = parse_provider(provider_doc(feed="https://feeds.example/opc/"))
    assert build._feed_root(https, inp) == "https://feeds.example/opc/"
    assert build._feed_root(parse_provider(provider_doc(feed="rel")), inp) == "rel"  # no base dir


def _stats():
    return {
        "generatedAt": "2026-10-02T00:00:00Z",
        "repos": {
            "example/clock": {
                "stars": 10,
                "vel30": 2,
                "lastCommit": "2026-09-01T00:00:00Z",
                "c90": 3,
                "contrib": 1,
                "bus": 1,
                "rel180": 0,
                "lastRelease": None,
                "issues": 0,
                "respH": None,
                "archived": False,
                "branch": "main",
                "images": ["https://raw.githubusercontent.com/example/clock/main/a.png"],
            },
            "example/suite": {
                "images": ["https://raw.githubusercontent.com/example/suite/main/top.png"],
                "dirImages": {
                    "plugins/a": ["https://raw.githubusercontent.com/example/suite/main/plugins/a/s.png"]
                },
            },
        },
        "engagement": {"example.clock": {"views": 5, "copies": 1, "hearts": 0}},
    }


def _ranking():
    return {
        "version": "ranking-v1",
        "factors": [{"id": "stars", "label": "log(stars)", "weight": 20}],
        "gates": {"safe": 1},
        "plugins": {"example.clock": {"rank": 1, "score": 4.2, "fac": [4.2]}},
        "shelves": {"top": ["example.clock"], "byCategory": {"Widgets": ["example.clock"]}},
    }


def test_snapshot_assemble(tmp_path):
    shutil.copytree(EXAMPLE_FEED, tmp_path / "provider-feed")
    agg = _run(tmp_path, registry_doc(provider_doc(), marketplace_provider_doc()))
    meta = snapshot.SnapshotMeta(T0, 100, T0 + dt.timedelta(days=7), True, "api/v1/")
    doc = snapshot.assemble(
        meta,
        agg.market,
        agg.rows,
        agg.combined,
        providers=[p.doc() for p in agg.providers],
        stats=_stats(),
        ranking=_ranking(),
    )
    assert schemas.errors(doc, "store") == []
    by = {p["id"]: p for p in doc["plugins"]}
    clock = by["example.clock"]
    assert clock["gh"]["stars"] == 10
    assert clock["gallery"] == ["https://raw.githubusercontent.com/example/clock/main/a.png"]
    assert clock["img"] == {
        "thumb": "assets/img/c.webp",
        "full": "assets/img/c-full.webp",
        "w": 1600,
        "h": 900,
    }
    assert clock["verdict"] == {
        "combined": "caution",
        "basis": "trusted",
        "contested": False,
        "commit": C1,
        "providers": {"example": "caution", "marketplace": "safe"},
    }
    assert (clock["rank"], clock["report"], clock["install"]) == (
        1,
        "plugins/example.clock.json",
        "omarchy plugin add https://github.com/example/clock.git",
    )
    suite = by["example.suite-a"]
    assert suite["path"] == "plugins/a"
    assert suite["gallery"] == ["https://raw.githubusercontent.com/example/suite/main/plugins/a/s.png"]
    assert "install" not in suite
    assert suite["gh"] is None
    assert suite["img"] is None
    assert by["omarchy.weather"]["verdict"]["combined"] == "unknown"
    assert by["omarchy.weather"]["report"] is None
    assert doc["catalog"] == {
        "generatedAt": "2026-10-01T00:00:00.000Z",
        "plugins": 4,
        "retired": 1,
        "builtin": 1,
    }
    assert doc["shelves"]["top"] == ["example.clock"]
    assert doc["shelves"]["trending"] == []
    assert doc["categories"] == [{"name": "Widgets", "count": 2}]
    bare = snapshot.assemble(meta, agg.market, {}, {}, providers=[], stats=None, ranking=None)
    assert schemas.errors(bare, "store") == []
    assert bare["ranking"]["version"] == "none"


@needs_ssh
def test_cli_end_to_end(tmp_path, capsys, monkeypatch):
    shutil.copytree(EXAMPLE_FEED, tmp_path / "provider-feed")
    (tmp_path / "providers.json").write_text(
        json.dumps(registry_doc(provider_doc(), marketplace_provider_doc()))
    )
    (tmp_path / "catalog.json").write_text(json.dumps(catalog()))
    (tmp_path / "registry.json").write_text(json.dumps(market_registry()))
    (tmp_path / "stats.json").write_text(json.dumps(_stats()))
    (tmp_path / "ranking.json").write_text(json.dumps(_ranking()))
    key = tmp_path / "keys" / "dev-key"
    assert cli.main(["keygen", "--key", str(key)]) == 0
    assert cli.main(["keygen", "--key", str(key)]) == 0  # second call: no overwrite
    lines = capsys.readouterr().out.strip().splitlines()
    allowed = tmp_path / "allowed_signers"
    allowed.write_text(lines[1] + "\n")
    assert cli.main(["sign", "registry", str(tmp_path / "providers.json"), "--key", str(key)]) == 0
    capsys.readouterr()
    common = [
        "--providers",
        str(tmp_path / "providers.json"),
        "--catalog",
        str(tmp_path / "catalog.json"),
        "--registry",
        str(tmp_path / "registry.json"),
        "--out",
        str(tmp_path / "out"),
        "--state",
        str(tmp_path / "state.json"),
        "--offline",
    ]
    monkeypatch.setattr(cli, "_verifiers", lambda offline: {"none": UnsignedDevVerifier()})
    assert (
        cli.main(
            [
                "build",
                *common,
                "--providers-sig",
                str(tmp_path / "providers.json.sig"),
                "--allowed-signers",
                str(allowed),
                "--stats",
                str(tmp_path / "stats.json"),
                "--ranking",
                str(tmp_path / "ranking.json"),
                "--sign-key",
                str(key),
            ]
        )
        == 0
    )
    summary = json.loads(capsys.readouterr().out)
    assert summary["plugins"] == 2
    assert summary["signature"]
    meta = json.loads((tmp_path / "out" / "api" / "v1" / "meta.json").read_text())
    assert meta["registry"]["signed"] is True
    store = tmp_path / "out" / "store.json"
    assert cli.main(["verify-snapshot", str(store), "--allowed-signers", str(allowed)]) == 0
    assert (
        cli.main(
            [
                "verify-snapshot",
                str(store),
                "--allowed-signers",
                str(allowed),
                "--min-version",
                str(summary["version"] + 1),
            ]
        )
        == 1
    )
    store.write_text(store.read_text().replace('"dev":true', '"dev":false'))
    assert cli.main(["verify-snapshot", str(store), "--allowed-signers", str(allowed)]) == 1
    # api-only build (no snapshot), unsigned dev registry accepted
    assert cli.main(["build", *common]) == 0
    # tampered registry signature
    (tmp_path / "providers.json").write_text(json.dumps(registry_doc(provider_doc(), version=6)))
    assert (
        cli.main(
            [
                "build",
                *common,
                "--providers-sig",
                str(tmp_path / "providers.json.sig"),
                "--allowed-signers",
                str(allowed),
            ]
        )
        == 2
    )
    # unsigned production registry refused
    (tmp_path / "providers.json").write_text(json.dumps(registry_doc(provider_doc(), dev=False, version=7)))
    assert cli.main(["build", *common]) == 2


@needs_ssh
def test_cli_verify_expired(tmp_path, capsys):
    key = tmp_path / "k"
    sshsig.keygen(key, "t")
    allowed = tmp_path / "allowed"
    allowed.write_text(sshsig.allowed_signers_line(key.with_name("k.pub").read_text()) + "\n")
    store = tmp_path / "store.json"
    store.write_text(json.dumps({"version": 1, "expires": "2020-01-01T00:00:00Z", "dev": True}))
    assert cli.main(["sign", "snapshot", str(store), "--key", str(key)]) == 0
    assert cli.main(["verify-snapshot", str(store), "--allowed-signers", str(allowed)]) == 1
    assert "expired" in capsys.readouterr().err


def test_publish_rejects_invalid_documents(tmp_path):
    with pytest.raises(publish.PublishError, match="store"):
        publish.write_store({"schemaVersion": 1}, tmp_path, None)


def test_verifiers_factory():
    v = cli._verifiers(offline=True)
    assert set(v) == {"sigstore", "none"}
    assert Path(cli.DEV_KEY).name == "dev-snapshot-key"
