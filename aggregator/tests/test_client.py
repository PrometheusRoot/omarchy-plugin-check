import dataclasses
import datetime as dt
import hashlib
import json
import shutil
from typing import Any

from hypothesis import given
from hypothesis import strategies as st
from opc_spec import schemas
from opc_spec.vocab import BUNDLE_FILES, SNAPSHOT_NAMESPACE

from opc_aggregator import cli, client, publish, snapshot, sshsig
from opc_aggregator.merge import combine
from opc_aggregator.model import Combined
from opc_aggregator.ports import Verified
from opc_aggregator.statements import row_from_statement

from .helpers import (
    EXAMPLE_FEED,
    T0,
    marketplace_provider_doc,
    provider,
    provider_doc,
    registry_doc,
    row,
    statement,
)
from .test_build import _ranking, _run, _stats, needs_ssh

WEEKS = [None] * 50 + [2, 1]


def _store(tmp_path) -> tuple[Any, dict[str, Any], dict[str, Any]]:
    shutil.copytree(EXAMPLE_FEED, tmp_path / "provider-feed")
    agg = _run(tmp_path, registry_doc(provider_doc(), marketplace_provider_doc()))
    meta = snapshot.SnapshotMeta(T0, 100, T0 + dt.timedelta(days=7), True, "api/v1/")
    stats: dict[str, Any] = _stats()
    stats["repos"]["example/clock"]["weeks"] = WEEKS
    doc = snapshot.assemble(
        meta,
        agg.market,
        agg.rows,
        agg.combined,
        providers=[p.doc() for p in agg.providers],
        stats=stats,
        ranking=_ranking(),
    )
    return agg, doc, stats


def test_home_has_only_the_rows_its_shelves_use(tmp_path):
    _, doc, _ = _store(tmp_path)
    home = client.home_doc(doc)
    assert schemas.errors(home, "store-home") == []
    assert [p["id"] for p in home["plugins"]] == ["example.clock"]
    assert "gallery" not in home["plugins"][0]
    assert home["total"] == len(doc["plugins"])
    assert home["counts"]["caution"] + home["counts"]["unknown"] == home["total"]
    assert home["counts"]["images"] == 1
    assert (home["version"], home["apiBase"]) == (100, "api/v1/")


def test_search_columns_round_trip(tmp_path):
    _, doc, _ = _store(tmp_path)
    s = client.search_doc(doc)
    assert schemas.errors(s, "store-search") == []
    n = s["n"]
    assert n == len(doc["plugins"])
    assert all(len(v) == n for k, v in s["cols"].items() if k != "prov")
    assert all(len(v) == n for v in s["cols"]["prov"])
    i = s["cols"]["id"].index("example.clock")
    c, d = s["cols"], s["dict"]
    assert d["author"][c["author"][i]] == "ex"
    assert d["cat"][c["cat"][i]] == "Widgets"
    assert d["verdict"][c["verdict"][i]] == "caution"
    assert (c["repo"][i], c["rank"][i], c["stars"][i], c["commit"][i]) == ("example/clock", 1, 10, "1" * 40)
    assert c["critF"][i] == 1 << d["criteria"].index("no-exec")
    assert c["flags"][i] & client.FLAG_DETAIL
    assert c["flags"][i] & client.FLAG_CUSTOM_INSTALL
    suite = c["id"].index("example.suite-a")
    assert c["flags"][suite] & client.FLAG_NO_INSTALL
    assert c["author"][suite] == -1
    assert c["repo"][suite] == "Example/Suite"
    weather = c["id"].index("omarchy.weather")
    assert c["flags"][weather] & client.FLAG_BUILTIN
    assert d["providers"] == ["example", "marketplace"]
    assert d["verdict"][c["prov"][0][i]] == "caution"
    only = client.search_doc(doc, detail_ids=[])
    assert not any(f & client.FLAG_DETAIL for f in only["cols"]["flags"])


@given(st.text(max_size=400))
def test_short_desc_is_bounded_and_a_prefix(text):
    out = client.short_desc(text)
    assert len(out) <= client.DESC_MAX
    norm = " ".join(text.split())
    assert out == norm or norm.startswith(out.removesuffix("…").rstrip())


def test_short_desc_and_repo_edges():
    assert client.short_desc("a  b\nc") == "a b c"
    cut = client.short_desc("word " * 100)
    assert cut.endswith("…")
    assert len(cut) <= client.DESC_MAX
    assert client.short_desc("x" * 300).startswith("x" * 150)
    assert client.short_repo("https://gitlab.com/a/b") == "https://gitlab.com/a/b"


def test_manifest_and_details_docs():
    m = client.manifest_doc(
        {
            "version": 7,
            "generatedAt": "2026-10-02T00:00:00Z",
            "expires": "2026-10-09T00:00:00Z",
            "dev": False,
        },
        [
            ("home", "store-home.json", b"{}"),
            ("search", "store-search.json", b"[]"),
            ("store", "store.json", b""),
        ],
    )
    assert schemas.errors(m, "store-manifest") == []
    assert m["files"][0]["sha256"] == hashlib.sha256(b"{}").hexdigest()
    assert m["files"][2]["size"] == 0
    d = client.details_doc(7, {"b.x": "0" * 64, "a.x": "1" * 64})
    assert list(d["docs"]) == ["a.x", "b.x"]
    assert schemas.errors(d, "store-details") == []


def test_detail_docs_for_every_plugin_with_listing_and_weeks(tmp_path):
    agg, doc, stats = _store(tmp_path)
    weeks = snapshot.weeks_by_plugin(agg.market, stats)
    assert weeks == {"example.clock": WEEKS}
    stats["repos"]["example/clock"]["weeks"] = [-1] * 52
    assert snapshot.weeks_by_plugin(agg.market, stats) == {}
    listings = publish.Listings(rows={p["id"]: p for p in doc["plugins"]}, weeks=weeks)
    out = tmp_path / "out"
    _, hashes = publish.write_api(agg, out, T0, registry_signed=False, listings=listings)
    assert set(hashes) == {p["id"] for p in doc["plugins"]} & set(agg.market.plugins)
    clock = json.loads((out / "plugins" / "example.clock.json").read_text())
    assert clock["activity"]["weeks"] == WEEKS
    assert clock["listing"]["gallery"] == ["https://raw.githubusercontent.com/example/clock/main/a.png"]
    weather = json.loads((out / "plugins" / "omarchy.weather.json").read_text())
    assert (weather["combined"]["basis"], weather["providers"]) == ("none", [])
    assert "activity" not in weather
    assert schemas.errors(weather, "api-plugin") == []
    data = (out / "plugins" / "example.clock.json").read_bytes()
    assert hashes["example.clock"] == hashlib.sha256(data).hexdigest()


def test_statement_report_reaches_the_row_and_the_risk():
    stmt = statement()
    stmt["predicate"]["criteria"] = {"checked": ["no-exec", "no-exec"], "failed": []}
    stmt["predicate"]["report"] = {"verdict": {"score": 137}}
    r = row_from_statement(stmt, provider("example"), _verified())
    assert r.detail["report"] == {"verdict": {"score": 137}}
    c = combine([r])
    v = snapshot._verdict([r], c)
    assert v["risk"] == 100
    assert v["criteria"] == {"checked": ["no-exec"], "failed": []}
    plain = row_from_statement(statement(), provider("example"), _verified())
    assert "report" not in plain.detail
    assert "risk" not in snapshot._verdict([plain], combine([plain]))
    untrusted = row("p", "community", "caution")
    assert snapshot.deciding_row([untrusted], combine([untrusted])) is None
    assert snapshot.deciding_row([r], Combined("blocked", "trusted", False, (), ())) is None
    no_crit = dataclasses.replace(r, criteria=None)
    assert "criteria" not in snapshot._verdict([no_crit], combine([no_crit]))


def _verified():
    return Verified(payload=b"", verification="unsigned-dev")


@needs_ssh
def test_write_bundle_signs_a_manifest_over_every_file(tmp_path):
    agg, doc, _ = _store(tmp_path)
    out = tmp_path / "out"
    listings = publish.Listings(rows={p["id"]: p for p in doc["plugins"]}, weeks={})
    _, hashes = publish.write_api(agg, out / "api" / "v1", T0, registry_signed=False, listings=listings)
    key = tmp_path / "k"
    sshsig.keygen(key, "t")
    allowed = tmp_path / "allowed"
    allowed.write_text(sshsig.allowed_signers_line(key.with_name("k.pub").read_text()) + "\n")
    publish.write_store(doc, out, key)
    manifest, sig = publish.write_bundle(doc, hashes, out, key)
    assert sig is not None
    data = manifest.read_bytes()
    assert sshsig.verify(data, sig, allowed, SNAPSHOT_NAMESPACE)
    m = json.loads(data)
    assert [f["role"] for f in m["files"]] == ["home", "search", "details", "store"]
    for f in m["files"]:
        assert hashlib.sha256((out / f["path"]).read_bytes()).hexdigest() == f["sha256"]
    details = json.loads((out / BUNDLE_FILES["details"]).read_text())
    assert details["docs"] == dict(sorted(hashes.items()))


def test_cli_client_bundle_from_an_existing_store(tmp_path, capsys):
    agg, doc, _ = _store(tmp_path)
    src = tmp_path / "src"
    publish.write_api(agg, src / "api" / "v1", T0, registry_signed=False)
    publish.write_store(doc, src, None)
    out = tmp_path / "bundle"
    assert cli.main(["client-bundle", str(src / "store.json"), "--out", str(out)]) == 0
    assert json.loads(capsys.readouterr().out)["details"] == 2
    assert (out / "store.json").is_file()
    assert (
        cli.main(
            ["client-bundle", str(out / "store.json"), "--api", str(src / "api" / "v1"), "--out", str(out)]
        )
        == 0
    )
    m = json.loads((out / BUNDLE_FILES["manifest"]).read_text())
    assert m["version"] == 100
