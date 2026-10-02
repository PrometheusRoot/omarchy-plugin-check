"""Network adapters: GitHub GraphQL with the `gh` CLI's token, and polite HTTPS GETs.

The token comes from `gh auth token` at run time, lives in memory only, and is sent only to
api.github.com. No other module talks to the network.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import urllib.error
import urllib.request
from typing import Any, Final

from opc_collector.ports import RateLimitedError, Response, TransientError

USER_AGENT: Final = (
    "omarchy-plugin-check-collector/0.1 (+https://github.com/PrometheusRoot/omarchy-plugin-check)"
)
GRAPHQL_URL: Final = "https://api.github.com/graphql"
MAX_BODY: Final = 64 * 1024 * 1024


class TokenError(Exception):
    """No GitHub token available from `gh auth token`."""


def gh_token() -> str:
    """The GitHub CLI's token for github.com (read-only use)."""
    gh = shutil.which("gh")
    if gh is None:
        raise TokenError("gh CLI not found; install it and run `gh auth login`")
    run = subprocess.run(
        [gh, "auth", "token", "--hostname", "github.com"], capture_output=True, text=True, check=False
    )
    token = run.stdout.strip()
    if run.returncode != 0 or not token:
        raise TokenError("`gh auth token` returned no token; run `gh auth login`")
    return token


def _retry_after(err: urllib.error.HTTPError) -> float:
    value = err.headers.get("Retry-After") if err.headers else None
    try:
        return float(value) if value else 60.0
    except ValueError:
        return 60.0


class GhGraphQL:
    """GraphQL port over urllib, authenticated with a token held in memory."""

    def __init__(self, token: str, timeout: float = 60.0) -> None:
        """`token` is never logged or written anywhere."""
        self._token = token
        self.timeout = timeout

    def query(self, text: str) -> dict[str, Any]:
        """POST one query; map throttling and server errors to the port's exceptions."""
        req = urllib.request.Request(
            GRAPHQL_URL,
            data=json.dumps({"query": text}).encode(),
            headers={
                "Authorization": f"bearer {self._token}",
                "User-Agent": USER_AGENT,
                "Content-Type": "application/json",
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:  # noqa: S310  # why: constant https URL
                body: bytes = resp.read(MAX_BODY)
        except urllib.error.HTTPError as err:
            if err.code in {403, 429}:
                raise RateLimitedError(_retry_after(err)) from err
            raise TransientError(f"HTTP {err.code}") from err
        except (OSError, TimeoutError) as err:
            raise TransientError(str(err)) from err
        try:
            doc: dict[str, Any] = json.loads(body)
        except ValueError as err:
            raise TransientError(f"invalid JSON: {err}") from err
        return doc


class UrllibHttp:
    """HTTPS GET with conditional headers (catalog, registry, engagement stats)."""

    def __init__(self, timeout: float = 60.0) -> None:
        """Configure the timeout in seconds."""
        self.timeout = timeout

    def get(self, url: str, etag: str | None = None, last_modified: str | None = None) -> Response:
        """GET; a 304 returns body None."""
        if not url.startswith("https://"):
            raise TransientError(f"refusing non-https URL {url}")
        headers = {"User-Agent": USER_AGENT}
        if etag:
            headers["If-None-Match"] = etag
        if last_modified:
            headers["If-Modified-Since"] = last_modified
        req = urllib.request.Request(url, headers=headers)  # noqa: S310  # why: scheme checked above
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:  # noqa: S310  # why: scheme checked above
                body: bytes = resp.read(MAX_BODY)
                return Response(
                    resp.status, body, resp.headers.get("ETag"), resp.headers.get("Last-Modified")
                )
        except urllib.error.HTTPError as err:
            if err.code == 304:
                return Response(304, None, etag, last_modified)
            raise TransientError(f"{url}: HTTP {err.code}") from err
        except OSError as err:
            raise TransientError(f"{url}: {err}") from err
