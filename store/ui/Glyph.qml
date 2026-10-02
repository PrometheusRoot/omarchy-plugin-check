pragma ComponentBehavior: Bound

import QtQuick
import "../lib/format.mjs" as F

// Outcome glyph in its outcome colour (safe green, caution yellow, risky orange, blocked
// red, unreviewed muted, stale blue). Hover shows the outcome name.
Ico {
    id: g

    property string outcome: "unreviewed"

    name: F.outcome(outcome).icon
    color: Theme.c(F.outcome(outcome).color)

    HoverHandler {
        id: hover
    }

    Tip {
        shown: hover.hovered
        label: g.outcome
    }
}
