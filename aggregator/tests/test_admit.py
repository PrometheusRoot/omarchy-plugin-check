import datetime as dt

from opc_aggregator import admit, marketplace
from opc_aggregator.model import Window, parse_registry

from .helpers import PTYPE, T0, catalog, market_registry, provider, provider_doc, registry_doc, statement


def _market():
    return marketplace.parse(catalog(), market_registry())


def why(reason: str | None) -> str:
    assert reason is not None
    return reason


def test_registry_reason():
    reg = parse_registry(registry_doc(provider_doc()))
    assert admit.registry_reason(reg, T0, None) is None
    assert admit.registry_reason(reg, T0, 5) is None
    assert "rollback" in why(admit.registry_reason(reg, T0, 6))
    assert "expired" in why(admit.registry_reason(reg, dt.datetime(2027, 1, 1, tzinfo=dt.UTC), None))


def _index(**kw):
    base = {
        "provider": "p",
        "predicateType": PTYPE,
        "generatedAt": "2026-10-01T00:00:00Z",
        "expires": "2026-10-20T00:00:00Z",
        "version": 7,
    }
    base.update(kw)
    return base


def test_feed_reason():
    p = provider()
    assert admit.feed_reason(_index(), p, PTYPE, T0, None) is None
    assert admit.feed_reason(_index(), p, PTYPE, T0, 7) is None
    assert "rollback" in why(admit.feed_reason(_index(), p, PTYPE, T0, 8))
    assert "provider" in why(admit.feed_reason(_index(provider="q"), p, PTYPE, T0, None))
    other = _index(predicateType="https://x/attestation/security-review/v1")
    assert "predicateType" in why(admit.feed_reason(other, p, PTYPE, T0, None))
    assert "expired" in why(admit.feed_reason(_index(expires="2026-10-02T00:00:00Z"), p, PTYPE, T0, None))
    assert "30 days" in why(admit.feed_reason(_index(expires="2026-11-15T00:00:00Z"), p, PTYPE, T0, None))


def test_signing_time_reason():
    w = Window(T0 - dt.timedelta(hours=1), T0 + dt.timedelta(hours=1), "workflow compromise")
    p = provider(valid_from=T0 - dt.timedelta(days=1), valid_until=T0 + dt.timedelta(days=1), excluded=(w,))
    assert admit.signing_time_reason(p, T0 - dt.timedelta(hours=2)) is None
    assert "before validFrom" in why(admit.signing_time_reason(p, T0 - dt.timedelta(days=2)))
    assert "after validUntil" in why(admit.signing_time_reason(p, T0 + dt.timedelta(days=1)))
    assert "workflow compromise" in why(admit.signing_time_reason(p, T0))
    assert admit.signing_time_reason(p, T0 + dt.timedelta(hours=1)) is None  # window is half-open


def _entry(stmt):
    return {
        "pluginId": stmt["predicate"]["plugin"]["id"],
        "commit": stmt["subject"][0]["digest"]["gitCommit"],
    }


def test_statement_reason_accepts_and_follows_migrations():
    m = _market()
    p = provider("example")
    s = statement()
    assert admit.statement_reason(s, _entry(s), p, m, PTYPE) is None
    moved = statement(repo="https://github.com/example/clock-old")
    assert admit.statement_reason(moved, _entry(moved), p, m, PTYPE) is None
    suite = statement(plugin="example.suite-a", repo="https://github.com/example/suite")
    assert admit.statement_reason(suite, _entry(suite), p, m, PTYPE) is None


def test_statement_reason_rejections():
    m = _market()
    p = provider("example")
    cases = {
        "predicateType": (statement(), {"predicateType": "https://x/attestation/security-review/v1"}),
    }
    s, patch = cases["predicateType"]
    s.update(patch)
    assert "predicateType" in why(admit.statement_reason(s, _entry(s), p, m, PTYPE))
    s = statement(provider="other")
    assert "names provider" in why(admit.statement_reason(s, _entry(s), p, m, PTYPE))
    s = statement()
    assert "index entry" in why(admit.statement_reason(s, {"pluginId": "x", "commit": "1" * 40}, p, m, PTYPE))
    s = statement(plugin="nope.nope")
    assert "unlisted" in why(admit.statement_reason(s, _entry(s), p, m, PTYPE))
    s = statement(plugin="old.thing", repo="https://github.com/old/thing")
    assert "retired" in why(admit.statement_reason(s, _entry(s), p, m, PTYPE))
    s = statement(plugin="omarchy.weather", repo="https://github.com/omacom/omarchy")
    assert "builtin" in why(admit.statement_reason(s, _entry(s), p, m, PTYPE))
    s = statement(repo="https://github.com/evil/clock")
    assert "marketplace repository" in why(admit.statement_reason(s, _entry(s), p, m, PTYPE))
    s = statement()
    for conflict in ("example", "example.clock"):
        p2 = provider("example", conflicts=frozenset({conflict}))
        assert "conflict" in why(admit.statement_reason(s, _entry(s), p2, m, PTYPE))
