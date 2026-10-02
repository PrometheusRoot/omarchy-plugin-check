"""SigstoreVerifier: keyless bundles (DSSE attestations, signed feed indexes) via sigstore-python.

The only module that imports `sigstore` (import contract). Identity policy = exact certificate SAN
+ OIDC issuer + GitHub workflow repository from the registry (spec/PROTOCOL.md §4). The signing time
used for validity windows is the Fulcio certificate's notBefore: certificates live ~10 minutes and
verification proves the signature was made while the certificate was valid.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from opc_spec.vocab import DSSE_PAYLOAD_TYPE
from sigstore.errors import Error as SigstoreError
from sigstore.models import Bundle
from sigstore.verify import Verifier as _SigVerifier
from sigstore.verify import policy

from opc_aggregator.ports import VerificationError, Verified

if TYPE_CHECKING:
    from opc_aggregator.model import Provider


class SigstoreVerifier:
    """Verifier port over sigstore-python (public-good Fulcio/Rekor trust root by default)."""

    def __init__(self, verifier: _SigVerifier | None = None, *, offline: bool = False) -> None:
        """`verifier` defaults to the production trust root (TUF refresh unless `offline`)."""
        self._verifier = verifier or _SigVerifier.production(offline=offline)

    @staticmethod
    def _policy(provider: Provider) -> policy.VerificationPolicy:
        if not (provider.identity and provider.issuer and provider.repository):
            raise VerificationError(f"{provider.id}: registry entry has no sigstore identity")
        return policy.AllOf(
            [
                policy.Identity(identity=provider.identity, issuer=provider.issuer),
                policy.GitHubWorkflowRepository(provider.repository),
            ]
        )

    @staticmethod
    def _bundle(data: bytes) -> Bundle:
        try:
            return Bundle.from_json(data)
        except (SigstoreError, ValueError) as exc:
            raise VerificationError(f"not a sigstore bundle: {exc}") from exc

    def verify_attestation(self, provider: Provider, data: bytes) -> Verified:
        """Verify a DSSE bundle; return the in-toto statement it carries."""
        pol = self._policy(provider)
        bundle = self._bundle(data)
        try:
            payload_type, payload = self._verifier.verify_dsse(bundle, pol)
        except SigstoreError as exc:
            raise VerificationError(f"{provider.id}: {exc}") from exc
        if payload_type != DSSE_PAYLOAD_TYPE:
            raise VerificationError(f"{provider.id}: unexpected DSSE payloadType {payload_type!r}")
        cert = bundle.signing_certificate
        return Verified(payload, "sigstore", provider.identity, cert.not_valid_before_utc)

    def verify_blob(self, provider: Provider, data: bytes, bundle: bytes | None) -> Verified:
        """Verify a message-signature bundle over `data` (feed index)."""
        if bundle is None:
            raise VerificationError(f"{provider.id}: index signature missing")
        pol = self._policy(provider)
        b = self._bundle(bundle)
        try:
            self._verifier.verify_artifact(data, b, pol)
        except SigstoreError as exc:
            raise VerificationError(f"{provider.id}: {exc}") from exc
        return Verified(data, "sigstore", provider.identity, b.signing_certificate.not_valid_before_utc)
