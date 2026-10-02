"""GitHub GraphQL batch query for catalog repositories (read-only). Pure: builds text, no I/O.

One query = up to N aliased `repository(owner:, name:)` blocks + `rateLimit`. Field choices are the
cheapest ones that answer docs/RANKING.md (point cost ≈ 1 per 100 requested nodes; see
https://docs.github.com/en/graphql/overview/rate-limits-and-query-limits-for-the-graphql-api).
Stargazer timestamps are not requested: GitHub no longer lists stargazers to non-owners (GraphQL
returns an empty connection, REST 404; checked 2026-10-02), so star velocity comes from our own
daily star-count history (stats.velocity).
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from typing import TYPE_CHECKING, Final

if TYPE_CHECKING:
    import datetime as dt
    from collections.abc import Sequence

_SAFE_NAME: Final = re.compile(r"^[A-Za-z0-9._-]{1,100}$")
_SAFE_DIR: Final = re.compile(r"^[A-Za-z0-9._/ -]{1,300}$")
README_NAMES: Final = ("README.md", "readme.md", "Readme.md", "README.MD", "README")
DIR_README_MAX: Final = 3
"""Plugin directories per repository whose own README we also read (monorepos / suites)."""


@dataclass(frozen=True)
class RepoRef:
    """One repository to query, with the plugin directories inside it ('' = root)."""

    key: str
    owner: str
    name: str
    dirs: tuple[str, ...] = ()

    def valid(self) -> bool:
        """True if owner/name are safe to inline into a query."""
        return bool(_SAFE_NAME.match(self.owner) and _SAFE_NAME.match(self.name))


_REPO_FIELDS: Final = """
    nameWithOwner isArchived pushedAt stargazerCount
    defaultBranchRef { name target { ... on Commit { oid
      recent: history(first: 100) { nodes { committedDate author { email user { login } } } }
      h90: history(since: %(since)s) { totalCount }
    } } }
    releases(first: 20, orderBy: {field: CREATED_AT, direction: DESC}) {
      totalCount nodes { publishedAt tagName }
    }
    openIssues: issues(states: OPEN) { totalCount }
    recentIssues: issues(last: 20, orderBy: {field: CREATED_AT, direction: ASC}) {
      nodes { createdAt author { login } comments(first: 5) { nodes { createdAt author { login } } } }
    }
"""


def _blob(alias: str, expression: str) -> str:
    return f"{alias}: object(expression: {json.dumps(expression)}) {{ ... on Blob {{ text }} }}"


def repo_block(alias: str, ref: RepoRef, since: dt.datetime) -> str:
    """One aliased repository selection (owner/name must be valid())."""
    readmes = [_blob(f"readme{i}", f"HEAD:{n}") for i, n in enumerate(README_NAMES)]
    dirs = [d for d in ref.dirs if d and _SAFE_DIR.match(d) and ".." not in d][:DIR_README_MAX]
    readmes += [_blob(f"dir{i}", f"HEAD:{d}/README.md") for i, d in enumerate(dirs)]
    fields = _REPO_FIELDS % {"since": json.dumps(since.strftime("%Y-%m-%dT%H:%M:%SZ"))}
    return (
        f"{alias}: repository(owner: {json.dumps(ref.owner)}, name: {json.dumps(ref.name)}) {{"
        f"{fields}    {' '.join(readmes)}\n  }}"
    )


def batch_query(refs: Sequence[RepoRef], since: dt.datetime) -> str:
    """The full query for a batch; aliases are r0..rN in input order."""
    blocks = "\n  ".join(repo_block(f"r{i}", r, since) for i, r in enumerate(refs))
    return f"query {{\n  rateLimit {{ cost remaining resetAt limit }}\n  {blocks}\n}}"


def readme_dirs(ref: RepoRef) -> list[str]:
    """The plugin dirs (in alias order dir0..) a query for `ref` reads READMEs for."""
    return [d for d in ref.dirs if d and _SAFE_DIR.match(d) and ".." not in d][:DIR_README_MAX]
