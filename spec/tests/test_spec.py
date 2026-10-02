import json
from pathlib import Path

import pytest
from hypothesis import given
from hypothesis import strategies as st

from opc_spec import ids, jsonv, schemas, vocab

ROOT = Path(__file__).resolve().parents[1]
EXAMPLES = ROOT / "examples"
ANY_VERDICT = st.sampled_from([*vocab.VERDICTS, "unknown", "bogus"])


# --- vocab ----------------------------------------------------------------------------------


def test_predicate_type_default_and_configurable():
    assert vocab.predicate_type() == (
        "https://prometheusroot.github.io/omarchy-plugin-check/attestation/security-review/v1"
    )
    assert (
        vocab.predicate_type("https://x.example/opc/")
        == "https://x.example/opc/attestation/security-review/v1"
    )


def test_rank_worst_cap_examples():
    assert [vocab.severity_rank(v) for v in ("safe", "caution", "risky", "blocked", "unknown")] == [
        0,
        1,
        2,
        3,
        -1,
    ]
    assert vocab.as_verdict(3) == "unknown"
    assert vocab.worst([]) == "unknown"
    assert vocab.worst(["unknown", "safe"]) == "safe"
    assert vocab.worst(["caution", "blocked", "safe"]) == "blocked"
    assert vocab.cap("blocked", "caution") == "caution"
    assert vocab.cap("safe", "caution") == "safe"
    assert vocab.cap("nope", "caution") == "unknown"


@given(st.lists(ANY_VERDICT))
def test_worst_is_order_independent_and_dominates(vs):
    w = vocab.worst(vs)
    assert w == vocab.worst(list(reversed(vs)))
    assert all(vocab.severity_rank(v) <= vocab.severity_rank(w) for v in vs)


@given(ANY_VERDICT, st.sampled_from(vocab.VERDICTS))
def test_cap_never_exceeds_ceiling_and_never_raises(v, ceiling):
    c = vocab.cap(v, ceiling)
    assert vocab.severity_rank(c) <= vocab.severity_rank(ceiling)
    assert vocab.severity_rank(c) <= max(vocab.severity_rank(v), -1)


def test_vocab_matches_schema_enums():
    common = schemas.schema("common")["$defs"]
    assert tuple(common["criterion"]["enum"]) == vocab.CRITERIA
    assert tuple(common["category"]["enum"]) == vocab.CATEGORIES
    assert tuple(common["severity"]["enum"]) == vocab.SEVERITIES
    assert tuple(common["tier"]["enum"]) == vocab.TIERS
    assert common["verdict"]["enum"] == [*vocab.VERDICTS, "unknown"]


def test_categories_match_report_findings_vocabulary():
    findings = json.loads((ROOT.parent / "schemas" / "findings.schema.json").read_text())
    assert tuple(findings["$defs"]["category"]["enum"]) == vocab.CATEGORIES


# --- ids ------------------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("url", "key"),
    [
        ("https://github.com/Owner/Repo", "owner/repo"),
        ("https://github.com/Owner/Repo.git", "owner/repo"),
        ("git@github.com:Owner/Repo.git", "owner/repo"),
        ("git+https://github.com/o/r.js/", "o/r.js"),
        ("ssh://git@github.com/o/r", "o/r"),
        ("https://gitlab.com/o/r", None),
        ("https://github.com/o", None),
        ("https://github.com/o/..", None),
    ],
)
def test_repo_key(url, key):
    assert ids.repo_key(url) == key


def test_subject_and_urls():
    assert ids.subject_name("https://github.com/LetsFG/LetsFG.git") == "git+https://github.com/LetsFG/LetsFG"
    assert ids.https_url("git@github.com:a/b") == "https://github.com/a/b"
    assert ids.https_url("nope") is None
    with pytest.raises(ValueError, match="GitHub"):
        ids.subject_name("https://example.com/a/b")
    assert ids.marketplace_url("omamail") == "https://plugins.omarchy.org/plugin.html?id=omamail"
    with pytest.raises(ValueError, match="plugin id"):
        ids.marketplace_url("a b&c")
    assert ids.is_sha1("a" * 40)
    assert not ids.is_sha1("A" * 40)
    assert not ids.is_sha1(None)


# --- schemas --------------------------------------------------------------------------------


def _load(p: Path):
    return json.loads(p.read_text(encoding="utf-8"))


def test_examples_validate():
    feed = EXAMPLES / "provider-feed" / "feed" / "v1"
    assert schemas.errors(_load(feed / "index.json"), "feed-index") == []
    for st_path in (feed / "statements").rglob("*.json"):
        assert schemas.errors(_load(st_path), "statement") == []
    assert schemas.errors(_load(EXAMPLES / "providers.example.json"), "providers") == []


def test_statement_rejects_rule_ids_and_bad_subjects():
    feed = EXAMPLES / "provider-feed" / "feed" / "v1"
    doc = _load(next((feed / "statements").rglob("*.json")))
    doc["predicate"]["findings"][0]["ruleId"] = "x.internal-rule"
    assert any("ruleId" in e for e in schemas.errors(doc, "statement"))
    doc["predicate"]["findings"][0].pop("ruleId")
    doc["subject"][0]["name"] = "https://github.com/a/b"
    assert schemas.errors(doc, "statement")
    with pytest.raises(ValueError, match="statement"):
        schemas.check(doc, "statement")
    doc["subject"][0]["name"] = "git+https://github.com/a/b"
    schemas.check(doc, "statement")


def test_relpath_rejects_traversal():
    feed = EXAMPLES / "provider-feed" / "feed" / "v1"
    idx = _load(feed / "index.json")
    for bad in ("../x.json", "/etc/passwd", "a/../../b"):
        idx["entries"][0]["path"] = bad
        assert schemas.errors(idx, "feed-index"), bad


def test_predicate_report_extension_resolves():
    feed = EXAMPLES / "provider-feed" / "feed" / "v1"
    doc = _load(next((feed / "statements").rglob("*.json")))
    doc["predicate"]["report"] = {"schemaVersion": 1}
    errs = schemas.errors(doc, "statement")
    assert errs
    assert all(e.startswith("predicate/report") for e in errs)


def test_schema_dirs_prefer_the_wheel_copy(tmp_path):
    (tmp_path / "pkg" / "_schemas").mkdir(parents=True)
    assert schemas._dirs(tmp_path / "pkg") == (
        tmp_path / "pkg" / "_schemas",
        tmp_path / "pkg" / "_report_schemas",
    )
    spec_dir, ext_dir = schemas._dirs()
    assert (spec_dir / "statement.schema.json").is_file()
    assert (ext_dir / "report.schema.json").is_file()


def test_jsonv_accessors():
    assert jsonv.obj({"a": 1}) == {"a": 1}
    assert jsonv.obj([1]) == {}
    assert jsonv.arr([1]) == [1]
    assert jsonv.arr("x") == []
    assert jsonv.objs([{"a": 1}, 2, None]) == [{"a": 1}]
    assert jsonv.strs(["a", 1]) == ["a"]
    assert jsonv.text("a") == "a"
    assert jsonv.text(1) is None
    assert jsonv.integer(3) == 3
    assert jsonv.integer(True) is None
    assert jsonv.integer("3") is None
