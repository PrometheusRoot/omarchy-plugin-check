"""Ports of the collector: a GraphQL endpoint and a plain HTTPS getter (adapters in `net`)."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Protocol


class TransientError(Exception):
    """Retry later or with a smaller batch (timeouts, 502/504, GitHub 'something went wrong')."""


class RateLimitedError(Exception):
    """GitHub asked us to wait (`retry_after` seconds)."""

    def __init__(self, retry_after: float) -> None:
        """Remember how long to wait."""
        super().__init__(f"rate limited; retry after {retry_after:.0f}s")
        self.retry_after = retry_after


class GraphQL(Protocol):
    """Executes one read-only GraphQL query and returns the decoded response document."""

    def query(self, text: str) -> dict[str, Any]:
        """Return {'data': ..., 'errors': [...]}. Raise TransientError / RateLimitedError."""
        ...


@dataclass(frozen=True)
class Response:
    """A conditional GET result: body None means 304 Not Modified."""

    status: int
    body: bytes | None
    etag: str | None
    last_modified: str | None


class Http(Protocol):
    """HTTPS GET with conditional request headers."""

    def get(self, url: str, etag: str | None = None, last_modified: str | None = None) -> Response:
        """GET `url`; send If-None-Match / If-Modified-Since when given."""
        ...
