from opc_aggregator import marketplace
from opc_aggregator.model import parse_provider

from .helpers import C1, catalog, market_registry, marketplace_provider_doc


def test_baseline_rows():
    m = marketplace.parse(catalog(), market_registry())
    p = parse_provider(marketplace_provider_doc())
    rows = marketplace.baseline_rows(market_registry(), m, p)
    assert set(rows) == {"example.clock", "example.suite-a"}
    clock = rows["example.clock"]
    assert (clock.verdict, clock.tier, clock.verification, clock.commit) == (
        "safe",
        "unsigned",
        "unsigned",
        C1,
    )
    assert clock.detail["capabilities"] == ["network"]
    suite = rows["example.suite-a"]
    assert (suite.verdict, suite.commit, suite.time_reviewed) == ("risky", None, None)
    assert suite.detail["findings"] == ["curl-pipe-shell"]
