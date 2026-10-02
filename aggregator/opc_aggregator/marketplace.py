"""The unsigned marketplace baseline source: registry.json automatedSecurityBaseline → rows.

Identity (plugins, states, migrations) lives in `opc_spec.marketplace` (shared with the collector).
Pure.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from opc_spec import ids
from opc_spec.jsonv import obj, objs, strs, text
from opc_spec.marketplace import Marketplace, Plugin, parse

from opc_aggregator.model import Provider, Row, parse_time

if TYPE_CHECKING:
    from collections.abc import Mapping
    from typing import Any

    from opc_spec.vocab import Verdict

__all__ = ["BASELINE_VERDICT", "Marketplace", "Plugin", "baseline_rows", "parse"]

BASELINE_VERDICT: dict[str, Verdict] = {
    "passed": "safe",
    "review-required": "caution",
    "needs-fixes": "risky",
}
"""registry.json automatedSecurityBaseline.outcome → verdict (raw; the tier caps it at caution)."""


def baseline_rows(registry: Mapping[str, Any], market: Marketplace, provider: Provider) -> dict[str, Row]:
    """One unsigned row per listed plugin with an automatedSecurityBaseline outcome we can map."""
    rows: dict[str, Row] = {}
    for src in objs(registry.get("sources")):
        base = obj(src.get("automatedSecurityBaseline"))
        verdict = BASELINE_VERDICT.get(str(base.get("outcome")))
        if verdict is None:
            continue
        checked = text(base.get("checkedAt"))
        commit = text(base.get("commit"))
        for pid in strs(base.get("pluginIds")):
            plugin = market.plugins.get(pid)
            if plugin is None or plugin.state != "listed":
                continue
            rows[pid] = Row(
                provider=provider.id,
                tier=provider.tier,
                verification="unsigned",
                verdict=verdict,
                has_evidence=False,
                commit=commit if ids.is_sha1(commit) else None,
                time_reviewed=parse_time(checked) if checked else None,
                summary=f"marketplace baseline: {base.get('outcome')}",
                detail={
                    "outcome": base.get("outcome"),
                    "findings": strs(base.get("findings"))[:20],
                    "capabilities": strs(base.get("capabilities"))[:20],
                    "enforcementMode": base.get("enforcementMode"),
                },
            )
    return rows
