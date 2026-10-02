import datetime as dt
import hashlib
import json
from pathlib import Path
from typing import Any

from opc_aggregator.model import Provider, Row

T0 = dt.datetime(2026, 10, 2, 12, 0, tzinfo=dt.UTC)
PTYPE = "https://prometheusroot.github.io/omarchy-plugin-check/attestation/security-review/v1"
SPEC = Path(__file__).resolve().parents[2] / "spec"
EXAMPLE_FEED = SPEC / "examples" / "provider-feed"
C1 = "1" * 40
C3 = "3" * 40


def catalog() -> dict[str, Any]:
    return {
        "generatedAt": "2026-10-01T00:00:00.000Z",
        "plugins": [
            {
                "id": "example.clock",
                "name": "Clock",
                "repo": "https://github.com/example/clock",
                "author": "ex",
                "category": "Widgets",
                "kind": "Bar widget",
                "tags": ["bar"],
                "verificationStatus": "verified",
                "listedAt": "2026-09-01T00:00:00.000Z",
                "repositoryUpdatedAt": "2026-09-20T00:00:00Z",
                "previewThumbnail": "assets/img/c.webp",
                "previewImage": "assets/img/c-full.webp",
                "previewWidth": 1600,
                "previewHeight": 900,
                "installCommand": "omarchy plugin add https://github.com/example/clock.git",
                "license": "MIT",
                "version": "1.0.0",
                "manifestPath": "manifest.json",
            },
            {
                "id": "example.suite-a",
                "name": "Suite A",
                "repo": "https://github.com/Example/Suite.git",
                "manifestPath": "plugins/a/manifest.json",
                "category": "Widgets",
                "installAvailable": False,
                "installCommand": "",
            },
            {"id": "old.thing", "name": "Old", "repo": "https://github.com/old/thing"},
            {
                "id": "omarchy.weather",
                "name": "Weather",
                "repo": "https://github.com/omacom/omarchy",
                "builtIn": True,
                "sourceType": "builtin",
            },
            {"id": "x y", "name": "bad id"},
            {"name": "no id"},
        ],
    }


def market_registry() -> dict[str, Any]:
    return {
        "retiredPluginIds": ["old.thing"],
        "repositoryMigrations": [
            {"fromRepository": "example/clock-old", "toRepository": "example/clock"},
            {"fromRepository": "a/a", "toRepository": "a/a"},
        ],
        "sources": [
            {
                "repo": "https://github.com/example/clock",
                "repositoryIdentity": {"previousRepositories": ["example/ancient-clock"]},
                "automatedSecurityBaseline": {
                    "outcome": "passed",
                    "commit": C1,
                    "checkedAt": "2026-09-30T00:00:00Z",
                    "pluginIds": ["example.clock"],
                    "findings": [],
                    "capabilities": ["network"],
                },
            },
            {
                "repo": "https://github.com/example/suite",
                "automatedSecurityBaseline": {
                    "outcome": "needs-fixes",
                    "commit": "nope",
                    "pluginIds": ["example.suite-a", "missing.id"],
                    "findings": ["curl-pipe-shell"],
                },
            },
            {
                "repo": "https://github.com/old/thing",
                "automatedSecurityBaseline": {"outcome": "review-required", "pluginIds": ["old.thing"]},
            },
            {
                "repo": "https://github.com/z/z",
                "automatedSecurityBaseline": {"outcome": "weird", "pluginIds": ["example.clock"]},
            },
            {"repo": "https://github.com/z/y"},
        ],
    }


def provider_doc(pid="example", tier="core", signing="none", feed="provider-feed", **kw) -> dict[str, Any]:
    doc: dict[str, Any] = {
        "id": pid,
        "name": pid.title(),
        "kind": "feed",
        "tier": tier,
        "feedUrl": feed,
        "signing": signing,
        "sigstore": None,
        "validFrom": "2026-01-01T00:00:00Z",
        "validUntil": None,
        "excludedWindows": [],
        "criteriaSupported": [],
        "conflictsOfInterest": [],
        "contact": "x",
    }
    if signing == "sigstore":
        doc["sigstore"] = {
            "oidcIssuer": "https://token.actions.githubusercontent.com",
            "certificateIdentity": "https://github.com/cli/cli/.github/workflows/deployment.yml@refs/heads/trunk",
            "repository": "cli/cli",
        }
    doc.update(kw)
    return doc


def marketplace_provider_doc() -> dict[str, Any]:
    return {
        "id": "marketplace",
        "name": "Marketplace",
        "kind": "marketplace-baseline",
        "tier": "unsigned",
        "feedUrl": "https://raw.githubusercontent.com/omacom/omarchy-plugin-marketplace/main/registry.json",
        "signing": "none",
        "sigstore": None,
        "validFrom": "2026-01-01T00:00:00Z",
        "validUntil": None,
        "excludedWindows": [],
        "criteriaSupported": [],
        "conflictsOfInterest": [],
        "contact": "x",
    }


def registry_doc(*providers, dev=True, version=5, expires="2026-12-01T00:00:00Z") -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "version": version,
        "generatedAt": "2026-10-01T00:00:00Z",
        "expires": expires,
        "predicateType": PTYPE,
        "dev": dev,
        "providers": list(providers),
    }


def provider(pid: str = "p", tier: Any = "core", **kw: Any) -> Provider:
    base: dict[str, Any] = {
        "id": pid,
        "name": pid,
        "kind": "feed",
        "tier": tier,
        "feed_url": "x",
        "signing": "none",
        "issuer": None,
        "identity": None,
        "repository": None,
        "valid_from": T0 - dt.timedelta(days=30),
        "valid_until": None,
    }
    base.update(kw)
    return Provider(**base)


def row(
    provider: str = "p",
    tier: Any = "core",
    verdict: Any = "safe",
    evidence: bool = False,
    commit: str | None = C1,
    t: dt.datetime | None = T0,
    **kw: Any,
) -> Row:
    return Row(
        provider=provider,
        tier=tier,
        verification="unsigned-dev",
        verdict=verdict,
        has_evidence=evidence,
        commit=commit,
        time_reviewed=t,
        **kw,
    )


def write_feed(
    root: Path,
    statements: dict[str, dict],
    *,
    provider="example",
    version=10,
    generated=T0,
    expires=None,
    tamper=None,
):
    """Write <root>/feed/v1/{index.json,statements/...}; statements maps relpath -> statement dict."""
    feed = root / "feed" / "v1"
    entries = []
    for rel, stmt in statements.items():
        p = feed / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        data = json.dumps(stmt).encode()
        p.write_bytes(data)
        pred = stmt["predicate"]
        entries.append(
            {
                "pluginId": pred["plugin"]["id"],
                "repo": stmt["subject"][0]["name"][4:],
                "commit": stmt["subject"][0]["digest"]["gitCommit"],
                "timeReviewed": pred["timeReviewed"],
                "verdict": pred["verdict"]
                if pred["verdict"] in ("safe", "caution", "risky", "blocked")
                else "unknown",
                "path": rel,
                "sha256": tamper or hashlib.sha256(data).hexdigest(),
            }
        )
    exp = expires or (generated + dt.timedelta(days=20))
    idx = {
        "schemaVersion": 1,
        "provider": provider,
        "version": version,
        "generatedAt": generated.isoformat().replace("+00:00", "Z"),
        "expires": exp.isoformat().replace("+00:00", "Z"),
        "predicateType": PTYPE,
        "entries": entries,
    }
    (feed / "index.json").write_text(json.dumps(idx))
    return idx


def statement(
    plugin="example.clock",
    repo="https://github.com/example/clock",
    commit=C1,
    verdict="caution",
    provider="example",
    findings=None,
    when="2026-10-01T12:00:00Z",
) -> dict[str, Any]:
    return {
        "_type": "https://in-toto.io/Statement/v1",
        "subject": [{"name": "git+" + repo, "digest": {"gitCommit": commit}}],
        "predicateType": PTYPE,
        "predicate": {
            "provider": {"id": provider, "scannerVersion": "1", "method": ["static"]},
            "plugin": {"id": plugin},
            "timeReviewed": when,
            "verdict": verdict,
            "criteria": {"checked": [], "failed": []},
            "scope": {"kind": "full", "path": ""},
            "findings": findings or [],
            "quality": {"score": 70},
        },
    }
