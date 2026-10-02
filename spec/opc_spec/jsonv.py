"""Typed accessors for untrusted JSON: always return the expected container type, never raise.

Used by every public component that walks marketplace or provider JSON, so strict type checking
holds without casts at each call site.
"""

from __future__ import annotations

from typing import Any, cast


def obj(value: object) -> dict[str, Any]:
    """`value` if it is a JSON object, else {}."""
    return cast("dict[str, Any]", value) if isinstance(value, dict) else {}


def arr(value: object) -> list[Any]:
    """`value` if it is a JSON array, else []."""
    return cast("list[Any]", value) if isinstance(value, list) else []


def objs(value: object) -> list[dict[str, Any]]:
    """The JSON objects inside an array (other items dropped)."""
    return [cast("dict[str, Any]", v) for v in arr(value) if isinstance(v, dict)]


def strs(value: object) -> list[str]:
    """The strings inside an array (other items dropped)."""
    return [v for v in arr(value) if isinstance(v, str)]


def text(value: object) -> str | None:
    """`value` if it is a string, else None."""
    return value if isinstance(value, str) else None


def integer(value: object) -> int | None:
    """`value` if it is an int (not a bool), else None."""
    return value if isinstance(value, int) and not isinstance(value, bool) else None
