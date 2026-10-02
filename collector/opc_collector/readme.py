"""README image URLs for the store gallery. Pure.

Extracts Markdown and HTML images, resolves relative paths against the commit the README was read
at (raw.githubusercontent.com/<owner>/<name>/<sha>/<dir>/...), rewrites GitHub blob links to raw,
and drops badges, SVGs and anything not https.
"""

from __future__ import annotations

import posixpath
import re
from typing import Final
from urllib.parse import unquote, urlsplit

_MD: Final = re.compile(r"!\[[^\]]*\]\(\s*<?([^)\s>]+)>?(?:\s+[\"'][^)]*[\"'])?\s*\)")
_HTML: Final = re.compile(r"<img\b[^>]*?\bsrc\s*=\s*[\"']([^\"']+)[\"']", re.IGNORECASE)
_BLOB: Final = re.compile(r"^https://github\.com/([^/]+)/([^/]+)/(?:blob|raw)/(.+)$")
_BADGE_HOSTS: Final = frozenset(
    {
        "img.shields.io",
        "shields.io",
        "badgen.net",
        "badge.fury.io",
        "codecov.io",
        "travis-ci.org",
        "travis-ci.com",
        "app.codacy.com",
        "api.codeclimate.com",
        "deepwiki.com",
        "star-history.com",
        "api.star-history.com",
        "contrib.rocks",
        "github-readme-stats.vercel.app",
        "visitor-badge.laobi.icu",
        "komarev.com",
        "ko-fi.com",
        "storage.ko-fi.com",
        "www.buymeacoffee.com",
        "cdn.buymeacoffee.com",
        "private-user-images.githubusercontent.com",
        "skillicons.dev",
        "readme-typing-svg.demolab.com",
    }
)
_IMAGE_EXT: Final = (".png", ".jpg", ".jpeg", ".gif", ".webp", ".avif")
_ASSET_HOSTS: Final = frozenset({"user-images.githubusercontent.com"})
MAX_IMAGES: Final = 8


def _is_image(url: str) -> bool:
    parts = urlsplit(url)
    host, path = parts.hostname or "", unquote(parts.path).lower()
    if parts.scheme != "https" or host in _BADGE_HOSTS or "badge" in path or path.endswith(".svg"):
        return False
    if host == "github.com" and path.startswith("/user-attachments/assets/"):
        return True
    return host in _ASSET_HOSTS or path.endswith(_IMAGE_EXT)


def _resolve(src: str, owner: str, name: str, ref: str, base_dir: str) -> str | None:
    src = src.strip()
    if src.startswith("//"):
        src = "https:" + src
    m = _BLOB.match(src)
    if m:
        return f"https://raw.githubusercontent.com/{m.group(1)}/{m.group(2)}/{m.group(3).split('?')[0]}"
    if re.match(r"^[a-z][a-z0-9+.-]*:", src, re.IGNORECASE):
        return src if src.lower().startswith("https://") else None
    rel = src.split("#")[0].split("?")[0]
    path = posixpath.normpath(rel.lstrip("/") if rel.startswith("/") else posixpath.join(base_dir, rel))
    if path.startswith("../") or path in {".", ".."}:
        return None
    return f"https://raw.githubusercontent.com/{owner}/{name}/{ref}/{path}"


def image_urls(markdown: str, owner: str, name: str, ref: str, base_dir: str = "") -> list[str]:
    """Up to MAX_IMAGES distinct screenshot-like image URLs, in document order."""
    found: list[tuple[int, str]] = [(m.start(), m.group(1)) for m in _MD.finditer(markdown)]
    found += [(m.start(), m.group(1)) for m in _HTML.finditer(markdown)]
    out: list[str] = []
    for _, src in sorted(found):
        url = _resolve(src, owner, name, ref, base_dir)
        if url and _is_image(url) and url not in out:
            out.append(url)
        if len(out) == MAX_IMAGES:
            break
    return out
