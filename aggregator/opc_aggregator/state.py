"""Anti-rollback state: the highest registry, feed and snapshot versions accepted so far."""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from typing import TYPE_CHECKING, Any, cast

if TYPE_CHECKING:
    from pathlib import Path


@dataclass
class State:
    """Last accepted versions (None = never seen)."""

    registry: int | None = None
    feeds: dict[str, int] = field(default_factory=dict[str, int])
    snapshot: int | None = None


def load(path: Path) -> State:
    """Read the state file; a missing file is an empty state."""
    if not path.is_file():
        return State()
    doc = cast("dict[str, Any]", json.loads(path.read_text(encoding="utf-8")))
    feeds = cast("dict[str, Any]", doc.get("feeds") or {})
    return State(
        registry=doc.get("registry"),
        feeds={str(k): int(v) for k, v in feeds.items()},
        snapshot=doc.get("snapshot"),
    )


def save(path: Path, st: State) -> None:
    """Write the state file atomically."""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(
        json.dumps({"registry": st.registry, "feeds": st.feeds, "snapshot": st.snapshot}, indent=2) + "\n",
        encoding="utf-8",
    )
    tmp.replace(path)
