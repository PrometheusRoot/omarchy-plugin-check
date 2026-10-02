"""Merge rules (ADR-0009). Golden cases are the cross-implementation contract (CLI, store app)."""

import datetime as dt

import pytest
from hypothesis import given
from hypothesis import strategies as st
from opc_spec.vocab import TRUSTED_TIERS, VERDICTS, severity_rank

from opc_aggregator.merge import combine, decided_tree, effective, latest_per_provider

from .helpers import C1, C3, T0, row

GOLDEN = [
    # (rows as (tier, verdict, evidence), combined verdict, basis, contested)
    ([], "unknown", "none", False),
    ([("core", "unknown", False)], "unknown", "none", False),
    ([("core", "safe", False)], "safe", "trusted", False),
    ([("core", "safe", False), ("unsigned", "caution", False)], "caution", "trusted", False),
    ([("core", "safe", False), ("unsigned", "risky", False)], "caution", "trusted", True),
    ([("core", "blocked", True)], "blocked", "trusted", False),
    ([("core", "blocked", False)], "risky", "trusted", False),
    ([("verified", "blocked", True), ("core", "safe", False)], "blocked", "trusted", True),
    ([("core", "caution", False), ("verified", "risky", False)], "risky", "trusted", False),
    ([("community", "blocked", True)], "caution", "untrusted", False),
    ([("unsigned", "safe", False)], "unknown", "untrusted", False),
    ([("unsigned", "safe", False), ("community", "safe", False)], "unknown", "untrusted", False),
    ([("unsigned", "risky", False)], "caution", "untrusted", False),
]


@pytest.mark.parametrize(("spec", "verdict", "basis", "contested"), GOLDEN)
def test_golden(spec, verdict, basis, contested):
    rows = [row(provider=f"p{i}", tier=t, verdict=v, evidence=e) for i, (t, v, e) in enumerate(spec)]
    c = combine(rows)
    assert (c.verdict, c.basis, c.contested) == (verdict, basis, contested)
    assert c.reasons


def test_effective_adjustments():
    assert effective(row(verdict="blocked")).adjustments == ("blocked-without-evidence",)
    e = effective(row(tier="community", verdict="blocked"))
    assert e.verdict == "caution"
    assert e.adjustments == ("blocked-without-evidence", "capped-at-caution")
    assert effective(row(tier="unsigned", verdict="caution")).adjustments == ()


def test_commits_and_reasons():
    c = combine(
        [
            row(provider="a", commit=C1, verdict="caution"),
            row(provider="b", commit=C3, verdict="safe"),
            row(provider="c", commit=None, verdict="safe"),
        ]
    )
    assert c.commits == (C1, C3)
    assert c.reasons == ("a [core]: caution",)
    c2 = combine([row(verdict="blocked")])
    assert c2.reasons == ("p [core]: blocked (blocked-without-evidence)",)


def test_latest_per_provider():
    old, new = row(provider="a", t=T0), row(provider="a", t=T0 + dt.timedelta(hours=1), verdict="risky")
    undated = row(provider="a", t=None, verdict="blocked")
    assert latest_per_provider([old, new, undated]) == [new]
    assert latest_per_provider([undated, old]) == [old]
    assert latest_per_provider([row(provider="b"), old]) == [old, row(provider="b")]


ROWS = st.lists(
    st.builds(
        row,
        provider=st.sampled_from(["a", "b", "c", "d"]),
        tier=st.sampled_from(["core", "verified", "community", "unsigned"]),
        verdict=st.sampled_from([*VERDICTS, "unknown"]),
        evidence=st.booleans(),
    ),
    max_size=6,
)


@given(ROWS)
def test_combined_never_exceeds_worst_raw(rows):
    c = combine(rows)
    assert severity_rank(c.verdict) <= max([severity_rank(r.verdict) for r in rows], default=-1)


@given(ROWS)
def test_blocked_only_from_trusted_with_evidence(rows):
    if combine(rows).verdict == "blocked":
        assert any(r.tier in TRUSTED_TIERS and r.verdict == "blocked" and r.has_evidence for r in rows)


@given(ROWS)
def test_never_safe_without_a_trusted_decided_row(rows):
    c = combine(rows)
    if not any(r.tier in TRUSTED_TIERS and r.verdict in VERDICTS for r in rows):
        assert c.verdict != "safe"
        assert c.basis != "trusted"


@given(ROWS, ROWS)
def test_adding_rows_never_lowers_severity(a, b):
    assert severity_rank(combine(a + b).verdict) >= severity_rank(combine(a).verdict)


@given(ROWS)
def test_order_independent(rows):
    c1, c2 = combine(rows), combine(list(reversed(rows)))
    assert (c1.verdict, c1.basis, c1.contested) == (c2.verdict, c2.basis, c2.contested)


T1, T2 = "a" * 40, "b" * 40


def test_decided_tree():
    """The tree of the single trusted commit; absent when it is ambiguous or not attested."""
    one = [row("p", "core", "safe", tree=T1), row("m", "unsigned", "safe", tree=T2)]
    assert decided_tree(one, combine(one)) == T1  # untrusted rows never supply it
    agree = [row("p", "core", tree=T1), row("q", "verified", "caution", tree=T1)]
    assert decided_tree(agree, combine(agree)) == T1
    disagree = [row("p", "core", tree=T1), row("q", "verified", tree=T2)]
    assert decided_tree(disagree, combine(disagree)) is None
    partial = [row("p", "core", tree=T1), row("q", "verified")]
    assert decided_tree(partial, combine(partial)) == T1
    undecided = [row("p", "core", tree=T1), row("q", "verified", "unknown", tree=T2)]
    assert decided_tree(undecided, combine(undecided)) == T1
    assert decided_tree([row("p", "core", tree="nope")], combine([row("p", "core")])) is None
    two = [row("p", "core", tree=T1), row("q", "core", commit=C3, tree=T2)]
    assert decided_tree(two, combine(two)) is None
    untrusted = [row("m", "unsigned", "caution", tree=T1)]
    assert decided_tree(untrusted, combine(untrusted)) is None
