"""Provider side of the feed (spec/PROTOCOL.md §3): check unsigned statements, build the signed index.

Pure: bytes and documents in, documents and problem strings out. `opc_spec.feed_cli` walks a feed
directory with these functions; a provider's signing workflow runs it before and after
`cosign attest-blob --statement` (ADR-0039), so it signs only statements that pass `problems` and
publishes an index whose every entry points at a bundle carrying exactly the committed statement.
"""

from __future__ import annotations

import base64
import binascii
import datetime as dt
import hashlib
import json
from typing import TYPE_CHECKING, Any, Final, cast

from opc_spec import schemas
from opc_spec.jsonv import obj, objs, text

if TYPE_CHECKING:
    from collections.abc import Iterable, Mapping

INDEX_TTL: Final = dt.timedelta(days=30)
"""Longest index lifetime the protocol allows (feed-index.schema.json `expires`)."""
BUNDLE_SUFFIX: Final = ".sigstore.json"


def _iso(t: dt.datetime) -> str:
    return t.astimezone(dt.UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def bundle_path(statement_path: str) -> str:
    """`statements/<id>/<commit>.json` → `statements/<id>/<commit>.sigstore.json`."""
    return statement_path.removesuffix(".json") + BUNDLE_SUFFIX


def parse(data: bytes) -> dict[str, Any] | None:
    """A JSON object from bytes, else None."""
    try:
        doc = json.loads(data)
    except (ValueError, UnicodeDecodeError):
        return None
    return cast("dict[str, Any]", doc) if isinstance(doc, dict) else None


def problems(path: str, data: bytes, *, provider: str, predicate_type: str) -> list[str]:
    """Why the statement at feed-relative `path` must not be signed ([] = sign it).

    The path must be `statements/<plugin id>/<subject commit>.json`, the bytes a schema-valid
    in-toto statement of `provider` with exactly `predicate_type` (the schema admits only GitHub
    repositories as subjects).
    """
    parts = path.split("/")
    if len(parts) != 3 or parts[0] != "statements" or not parts[2].endswith(".json"):
        return [f"{path}: not statements/<plugin id>/<commit>.json"]
    doc = parse(data)
    if doc is None:
        return [f"{path}: not a JSON object"]
    errs = schemas.errors(doc, "statement")
    if errs:
        return [f"{path}: {e}" for e in errs[:3]]
    pred = obj(doc.get("predicate"))
    subject = objs(doc.get("subject"))[0]
    out: list[str] = []
    if obj(pred.get("provider")).get("id") != provider:
        out.append(f"{path}: provider is not {provider!r}")
    if doc.get("predicateType") != predicate_type:
        out.append(f"{path}: predicateType is not {predicate_type!r}")
    if obj(pred.get("plugin")).get("id") != parts[1]:
        out.append(f"{path}: plugin id does not match its directory")
    if f"{obj(subject.get('digest')).get('gitCommit')}.json" != parts[2]:
        out.append(f"{path}: subject commit does not match the file name")
    return out


def dsse_payload(bundle: bytes) -> bytes | None:
    """The DSSE payload a Sigstore bundle carries (unverified; verification is the consumer's job)."""
    payload = text(obj(obj(parse(bundle)).get("dsseEnvelope")).get("payload"))
    if payload is None:
        return None
    try:
        return base64.b64decode(payload, validate=True)
    except binascii.Error:
        return None


def bundle_matches(statement: bytes, bundle: bytes) -> bool:
    """True if `bundle` carries `statement` (as JSON: a signer may re-serialize it)."""
    payload = dsse_payload(bundle)
    return payload is not None and parse(payload) is not None and parse(payload) == parse(statement)


def entry(path: str, statement: Mapping[str, Any], bundle: bytes) -> dict[str, Any]:
    """The index entry for a checked statement (`problems` == []) and its bundle's bytes."""
    pred = obj(statement.get("predicate"))
    subject = objs(statement.get("subject"))[0]
    digest = obj(subject.get("digest"))
    out: dict[str, Any] = {
        "pluginId": obj(pred.get("plugin"))["id"],
        "repo": str(subject["name"]).removeprefix("git+"),
        "commit": digest["gitCommit"],
        "timeReviewed": pred["timeReviewed"],
        "verdict": pred["verdict"],
        "path": bundle_path(path),
        "sha256": hashlib.sha256(bundle).hexdigest(),
    }
    if "gitTree" in digest:
        out["tree"] = digest["gitTree"]
    return out


def index(  # noqa: PLR0913  # why: keyword-only fields of the one document it builds
    entries: Iterable[Mapping[str, Any]],
    *,
    provider: str,
    predicate_type: str,
    now: dt.datetime,
    previous_version: int = 0,
    ttl: dt.timedelta = INDEX_TTL,
) -> dict[str, Any]:
    """feed/v1/index.json: entries sorted by path, `version` above `previous_version`, expiring ≤ 30 days.

    Raises ValueError if the result does not validate against feed-index.schema.json.
    """
    doc: dict[str, Any] = {
        "schemaVersion": 1,
        "provider": provider,
        "version": max(int(now.timestamp()), previous_version + 1),
        "generatedAt": _iso(now),
        "expires": _iso(now + min(ttl, INDEX_TTL)),
        "predicateType": predicate_type,
        "entries": sorted((dict(e) for e in entries), key=lambda e: str(e["path"])),
    }
    errs = schemas.errors(doc, "feed-index")
    if errs:
        raise ValueError("index invalid: " + "; ".join(errs[:3]))
    return doc
