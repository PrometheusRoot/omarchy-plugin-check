"""Fetcher adapters: HTTPS (feeds in production) and local files (dev registries, tests)."""

from __future__ import annotations

import urllib.request
from pathlib import Path
from typing import Final

from opc_aggregator.ports import FetchError

MAX_BYTES: Final = 32 * 1024 * 1024
USER_AGENT: Final = "omarchy-plugin-check-aggregator/0.1"


class HttpsFetcher:
    """GET over HTTPS only, with a timeout and a size cap."""

    def __init__(self, timeout: float = 30.0, max_bytes: int = MAX_BYTES) -> None:
        """Configure timeout (seconds) and the largest accepted body."""
        self.timeout = timeout
        self.max_bytes = max_bytes

    def get(self, location: str) -> bytes:
        """Fetch `location` (must be https://)."""
        if not location.startswith("https://"):
            raise FetchError(f"refusing non-https URL: {location}")
        req = urllib.request.Request(location, headers={"User-Agent": USER_AGENT})  # noqa: S310  # why: scheme checked above
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:  # noqa: S310  # why: scheme checked above
                body: bytes = resp.read(self.max_bytes + 1)
        except OSError as exc:
            raise FetchError(f"{location}: {exc}") from exc
        if len(body) > self.max_bytes:
            raise FetchError(f"{location}: larger than {self.max_bytes} bytes")
        return body


class LocalFetcher:
    """Reads files below one root directory (no escaping it)."""

    def __init__(self, root: Path) -> None:
        """Serve files below `root`."""
        self.root = root.resolve()

    def get(self, location: str) -> bytes:
        """Read `location` (a path); it must resolve inside the root."""
        path = Path(location).resolve()
        if not path.is_relative_to(self.root):
            raise FetchError(f"{location}: outside {self.root}")
        try:
            return path.read_bytes()
        except OSError as exc:
            raise FetchError(f"{location}: {exc}") from exc


class RoutingFetcher:
    """https:// → HttpsFetcher; anything else → LocalFetcher (only when local reads are allowed)."""

    def __init__(self, https: HttpsFetcher, local: LocalFetcher | None) -> None:
        """`local` None = remote feeds only (production registries)."""
        self.https = https
        self.local = local

    def get(self, location: str) -> bytes:
        """Dispatch by scheme."""
        if location.startswith("https://"):
            return self.https.get(location)
        if self.local is None:
            raise FetchError(f"local feed not allowed outside dev registries: {location}")
        return self.local.get(location)
