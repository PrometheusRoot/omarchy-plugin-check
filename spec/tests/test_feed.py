import base64
import datetime as dt
import hashlib
import json
import shutil
from pathlib import Path

import pytest

from opc_spec import feed, feed_cli, vocab

EXAMPLE = Path(__file__).resolve().parents[1] / "examples" / "provider-feed" / "feed" / "v1"
REL = "statements/example.clock/1111111111111111111111111111111111111111.json"
PT = vocab.predicate_type()
NOW = dt.datetime(2026, 10, 3, 12, 0, tzinfo=dt.UTC)


def statement() -> dict:
    return json.loads((EXAMPLE / REL).read_bytes())


def raw(doc: object) -> bytes:
    return json.dumps(doc).encode()


def bundle_for(data: bytes) -> bytes:
    return raw({"dsseEnvelope": {"payload": base64.b64encode(data).decode(), "payloadType": "x"}})


def check(rel: str, doc: object, provider: str = "example") -> list[str]:
    data = doc if isinstance(doc, bytes) else raw(doc)
    return feed.problems(rel, data, provider=provider, predicate_type=PT)


# --- pure ---------------------------------------------------------------------------------------


def test_a_valid_statement_has_no_problems():
    assert check(REL, statement()) == []


@pytest.mark.parametrize(
    "rel",
    ["index.json", "statements/a.json", "other/example.clock/1.json", "statements/example.clock/x.txt"],
)
def test_paths_outside_the_layout_are_refused(rel):
    assert check(rel, statement()) == [f"{rel}: not statements/<plugin id>/<commit>.json"]


def test_non_objects_and_schema_errors_are_refused():
    assert check(REL, b"[1]") == [f"{REL}: not a JSON object"]
    assert check(REL, b"\xff") == [f"{REL}: not a JSON object"]
    bad = statement() | {"extra": 1}
    assert check(REL, bad)[0].startswith(REL + ": ")


def test_identity_mismatches_are_listed():
    doc = statement()
    doc["predicateType"] = "https://evil.example/attestation/security-review/v1"
    other = "statements/other.id/2222222222222222222222222222222222222222.json"
    assert check(other, doc, provider="opc") == [
        f"{other}: provider is not 'opc'",
        f"{other}: predicateType is not {PT!r}",
        f"{other}: plugin id does not match its directory",
        f"{other}: subject commit does not match the file name",
    ]


def test_bundle_path_and_payload():
    assert feed.bundle_path(REL).endswith("/1111111111111111111111111111111111111111.sigstore.json")
    data = raw(statement())
    assert feed.dsse_payload(bundle_for(data)) == data
    assert feed.dsse_payload(b"{}") is None
    assert feed.dsse_payload(b"not json") is None
    assert feed.dsse_payload(raw({"dsseEnvelope": {"payload": "%%%"}})) is None


def test_bundle_matches_compares_json_not_bytes():
    data = raw(statement())
    pretty = json.dumps(statement(), indent=2).encode()
    assert feed.bundle_matches(data, bundle_for(pretty))
    assert not feed.bundle_matches(data, bundle_for(raw(statement() | {"x": 1})))
    assert not feed.bundle_matches(data, bundle_for(b"not json"))
    assert not feed.bundle_matches(data, b"{}")


def test_entry_and_index():
    doc = statement()
    bundle = bundle_for(raw(doc))
    e = feed.entry(REL, doc, bundle)
    assert e == {
        "pluginId": "example.clock",
        "repo": doc["subject"][0]["name"].removeprefix("git+"),
        "commit": "1" * 40,
        "timeReviewed": doc["predicate"]["timeReviewed"],
        "verdict": doc["predicate"]["verdict"],
        "path": feed.bundle_path(REL),
        "sha256": hashlib.sha256(bundle).hexdigest(),
    } | ({"tree": doc["subject"][0]["digest"]["gitTree"]} if "gitTree" in doc["subject"][0]["digest"] else {})
    doc["subject"][0]["digest"]["gitTree"] = "2" * 40
    assert feed.entry(REL, doc, bundle)["tree"] == "2" * 40
    del doc["subject"][0]["digest"]["gitTree"]
    assert "tree" not in feed.entry(REL, doc, bundle)

    idx = feed.index([e], provider="example", predicate_type=PT, now=NOW)
    assert idx["version"] == int(NOW.timestamp())
    assert idx["generatedAt"] == "2026-10-03T12:00:00Z"
    assert idx["expires"] == "2026-11-02T12:00:00Z"
    later = feed.index(
        [e], provider="example", predicate_type=PT, now=NOW, previous_version=2**40, ttl=dt.timedelta(days=99)
    )
    assert later["version"] == 2**40 + 1
    assert later["expires"] == "2026-11-02T12:00:00Z"  # capped at 30 days
    with pytest.raises(ValueError, match="index invalid"):
        feed.index([e], provider="Not An Id", predicate_type=PT, now=NOW)


# --- cli ----------------------------------------------------------------------------------------


@pytest.fixture
def tree(tmp_path: Path) -> Path:
    root = tmp_path / "feed" / "v1"
    (root / REL).parent.mkdir(parents=True)
    shutil.copy(EXAMPLE / REL, root / REL)
    return root


def run(*argv: str) -> int:
    return feed_cli.main(list(argv))


def test_check_lists_pending_then_index_needs_bundles(tree: Path, capsys):
    assert run("check", str(tree), "--provider", "example") == 0
    assert capsys.readouterr().out.splitlines() == [REL]
    assert run("index", str(tree), "--provider", "example") == 1
    assert "not signed yet" in capsys.readouterr().err


def test_index_after_signing_and_rollforward(tree: Path, capsys):
    (tree / feed.bundle_path(REL)).write_bytes(bundle_for((tree / REL).read_bytes()))
    assert run("check", str(tree), "--provider", "example") == 0
    assert capsys.readouterr().out == ""
    (tree / "index.json").write_text(json.dumps({"version": 2**40}))
    assert run("index", str(tree), "--provider", "example", "--ttl-days", "7") == 0
    idx = json.loads((tree / "index.json").read_text())
    assert idx["version"] == 2**40 + 1
    assert [e["path"] for e in idx["entries"]] == [feed.bundle_path(REL)]
    assert "1 entries" in capsys.readouterr().out
    (tree / "index.json").write_text("garbage")
    assert run("index", str(tree), "--provider", "example") == 0


def test_a_changed_statement_or_wrong_provider_fails(tree: Path, capsys):
    (tree / feed.bundle_path(REL)).write_bytes(bundle_for(raw(statement() | {"x": 1})))
    assert run("check", str(tree), "--provider", "example") == 1
    assert "different statement" in capsys.readouterr().err
    assert run("check", str(tree), "--provider", "opc") == 1
    assert "provider is not 'opc'" in capsys.readouterr().err
    assert run("index", str(tree), "--provider", "example") == 1
