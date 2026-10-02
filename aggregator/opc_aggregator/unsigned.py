"""UnsignedDevVerifier: accepts bare statements (or unsigned DSSE envelopes) for dev registries only.

Rows it produces are marked `unsigned-dev`; `build` refuses to use it unless the registry has
`dev: true` and the provider has `signing: none`. Never part of a published snapshot.
"""

from __future__ import annotations

import base64
import binascii
import json
from typing import TYPE_CHECKING, Any, cast

from opc_spec.vocab import DSSE_PAYLOAD_TYPE

from opc_aggregator.ports import VerificationError, Verified

if TYPE_CHECKING:
    from opc_aggregator.model import Provider


class UnsignedDevVerifier:
    """Verifier port that authenticates nothing; it only unwraps."""

    def verify_attestation(self, provider: Provider, data: bytes) -> Verified:
        """Return the statement bytes from a bare statement or a DSSE envelope's payload."""
        try:
            doc: Any = json.loads(data)
        except ValueError as exc:
            raise VerificationError(f"{provider.id}: not JSON: {exc}") from exc
        if isinstance(doc, dict) and "payload" in doc:
            env = cast("dict[str, Any]", doc)
            if env.get("payloadType") != DSSE_PAYLOAD_TYPE:
                raise VerificationError(f"{provider.id}: unexpected DSSE payloadType")
            try:
                return Verified(base64.b64decode(str(env["payload"]), validate=True), "unsigned-dev")
            except binascii.Error as exc:
                raise VerificationError(f"{provider.id}: bad DSSE payload: {exc}") from exc
        return Verified(data, "unsigned-dev")

    def verify_blob(
        self, provider: Provider, data: bytes, bundle: bytes | None
    ) -> Verified:  # why: port signature; unsigned feeds have no bundle
        """Accept the index as-is."""
        return Verified(data, "unsigned-dev")
