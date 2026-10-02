"""Ports: how the aggregator gets bytes (Fetcher) and decides who signed them (Verifier).

Adapters: `fetch.HttpsFetcher` / `fetch.LocalFetcher`; `sigstore_verifier.SigstoreVerifier` (the only
module that imports sigstore) and `unsigned.UnsignedDevVerifier` (dev registries only). Tests use
fakes from tests/fakes.py.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING, Protocol

if TYPE_CHECKING:
    import datetime as dt

    from opc_aggregator.model import Provider, Verification


class FetchError(Exception):
    """A feed file could not be retrieved."""


class VerificationError(Exception):
    """A signature did not verify against the provider's registry identity."""


@dataclass(frozen=True)
class Verified:
    """Authenticated payload plus who signed it and when (None when unsigned)."""

    payload: bytes
    verification: Verification
    signer: str | None = None
    signed_at: dt.datetime | None = None


class Fetcher(Protocol):
    """Retrieves a file by absolute URL or path."""

    def get(self, location: str) -> bytes:
        """Return the bytes at `location`; raise FetchError."""
        ...


class Verifier(Protocol):
    """Checks a provider's signatures against its registry identity."""

    def verify_attestation(self, provider: Provider, data: bytes) -> Verified:
        """Verify one attestation file; return the in-toto statement bytes. Raise VerificationError."""
        ...

    def verify_blob(self, provider: Provider, data: bytes, bundle: bytes | None) -> Verified:
        """Verify a detached signature over `data` (the feed index). Raise VerificationError."""
        ...
