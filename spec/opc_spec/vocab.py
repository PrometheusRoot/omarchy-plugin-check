"""Provider protocol v1 vocabulary: verdicts, tiers, criteria, finding categories, URIs, namespaces.

Pure constants and total functions over them. Everything public about the protocol that is not a
JSON Schema lives here, so the aggregator, the collector and providers share one definition.
"""

from __future__ import annotations

from typing import Final, Literal

STATEMENT_TYPE: Final = "https://in-toto.io/Statement/v1"
DSSE_PAYLOAD_TYPE: Final = "application/vnd.in-toto+json"
DEFAULT_BASE_URL: Final = "https://prometheusroot.github.io/omarchy-plugin-check"
PREDICATE_PATH: Final = "/attestation/security-review/v1"

SNAPSHOT_NAMESPACE: Final = "omarchy-plugin-check-snapshot"
"""`ssh-keygen -Y sign -n` namespace for store.json (a signature for another use cannot be replayed)."""
REGISTRY_NAMESPACE: Final = "omarchy-plugin-check-providers"
"""`ssh-keygen -Y sign -n` namespace for providers.json."""

STORE_KIND: Final = "omarchy-plugin-check/store"
MANIFEST_KIND: Final = "omarchy-plugin-check/store-manifest"
HOME_KIND: Final = "omarchy-plugin-check/store-home"
SEARCH_KIND: Final = "omarchy-plugin-check/store-search"
DETAILS_KIND: Final = "omarchy-plugin-check/store-details"
BUNDLE_FILES: Final = {
    "manifest": "store-manifest.json",
    "home": "store-home.json",
    "search": "store-search.json",
    "details": "store-details.json",
}
"""The store app's client bundle (ADR-0032), next to store.json. Only the manifest is signed (with
SNAPSHOT_NAMESPACE); it carries the sha256 of the others, and `kind` keeps the two documents apart."""

Verdict = Literal["safe", "caution", "risky", "blocked", "unknown"]
VERDICTS: Final[tuple[Verdict, ...]] = ("safe", "caution", "risky", "blocked")
"""Known verdicts, least to most severe. `unknown` is outside the order: it never wins a worst-of."""

Tier = Literal["core", "verified", "community", "unsigned"]
TIERS: Final[tuple[Tier, ...]] = ("core", "verified", "community", "unsigned")
TRUSTED_TIERS: Final[frozenset[str]] = frozenset({"core", "verified"})
"""Tiers whose verdicts count uncapped in the combined verdict (ADR-0009)."""

CRITERIA: Final = (
    "safe-to-run",
    "no-network",
    "no-exec",
    "no-persistence",
    "no-privilege",
    "no-obfuscation",
    "no-secrets",
    "reviewed-by-human",
)
CATEGORIES: Final = (
    "exec",
    "network",
    "persistence",
    "privilege",
    "obfuscation",
    "injection",
    "secret",
    "filesystem",
    "package",
    "supply-chain",
    "quality",
    "performance",
    "external-code",
    "other",
)
SEVERITIES: Final = ("info", "low", "medium", "high", "critical")
METHODS: Final = ("static", "ai", "manual", "dynamic")


def predicate_type(base_url: str = DEFAULT_BASE_URL) -> str:
    """The predicateType URI for a deployment base URL (no trailing slash)."""
    return base_url.rstrip("/") + PREDICATE_PATH


_RANK: Final[dict[str, Verdict]] = {v: v for v in VERDICTS}


def as_verdict(value: object) -> Verdict:
    """`value` if it is a known verdict, else `unknown` (total; never raises)."""
    return _RANK.get(value, "unknown") if isinstance(value, str) else "unknown"


def severity_rank(verdict: str) -> int:
    """0..3 for known verdicts (safe..blocked), -1 for `unknown` or anything else."""
    v = as_verdict(verdict)
    return -1 if v == "unknown" else VERDICTS.index(v)


def worst(verdicts: list[str]) -> Verdict:
    """Most severe known verdict, or `unknown` when none is known."""
    best: Verdict = "unknown"
    for v in verdicts:
        if severity_rank(v) > severity_rank(best):
            best = as_verdict(v)
    return best


def cap(verdict: str, ceiling: Verdict) -> Verdict:
    """`verdict` lowered to `ceiling` if it is more severe; `unknown` stays `unknown`."""
    v = as_verdict(verdict)
    return ceiling if severity_rank(v) > severity_rank(ceiling) else v
