"""Identifiers shared by every public component: repo keys, subject names, plugin ids, marketplace links.

Pure and total: malformed input yields `None` (or raises `ValueError` where documented), never I/O.
"""

from __future__ import annotations

import re
from typing import Final

SHA1: Final = re.compile(r"^[0-9a-f]{40}$")
PLUGIN_ID: Final = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
PROVIDER_ID: Final = re.compile(r"^[a-z][a-z0-9-]{1,31}$")
_GITHUB: Final = re.compile(
    r"^(?:git\+)?(?:https://|ssh://git@|git@)github\.com[/:]"
    r"(?P<owner>[A-Za-z0-9](?:[A-Za-z0-9-]{0,38}))/(?P<name>[A-Za-z0-9._-]{1,100}?)(?:\.git)?/?$"
)
MARKETPLACE_PLUGIN_URL: Final = "https://plugins.omarchy.org/plugin.html?id="


def github_repo(url: str) -> tuple[str, str] | None:
    """(owner, name) with original casing for a GitHub https/ssh/git+https URL, else None."""
    m = _GITHUB.match(url.strip())
    if not m or m.group("name") in {".", ".."}:
        return None
    return m.group("owner"), m.group("name")


def repo_key(url: str) -> str | None:
    """Case-folded 'owner/name' for a GitHub URL (the join key across sources), else None."""
    r = github_repo(url)
    return f"{r[0]}/{r[1]}".lower() if r else None


def https_url(url: str) -> str | None:
    """Canonical 'https://github.com/<owner>/<name>' (original casing), else None."""
    r = github_repo(url)
    return f"https://github.com/{r[0]}/{r[1]}" if r else None


def subject_name(url: str) -> str:
    """in-toto subject name 'git+https://github.com/<owner>/<name>'. Raises ValueError for non-GitHub URLs."""
    canon = https_url(url)
    if canon is None:
        raise ValueError(f"not a GitHub repository URL: {url!r}")
    return "git+" + canon


def marketplace_url(plugin_id: str) -> str:
    """The marketplace page for a plugin id (the only place we link for plugin details).

    Raises ValueError for a string that is not a plugin id (ids need no URL escaping).
    """
    if not PLUGIN_ID.match(plugin_id):
        raise ValueError(f"not a plugin id: {plugin_id!r}")
    return MARKETPLACE_PLUGIN_URL + plugin_id


def is_sha1(value: object) -> bool:
    """True for a lowercase 40-hex git object id."""
    return isinstance(value, str) and bool(SHA1.match(value))
