pragma ComponentBehavior: Bound

import QtQuick

// "providers  opc ⛨  mkt unsigned" (mockup hero meta line): one entry per provider row in
// the snapshot verdict, short name + glyph; unsigned tiers are labelled.
Row {
    id: pl

    property var rec: null
    readonly property var provs: Store.meta.providers || []

    spacing: 10

    function short(id) {
        return id === "marketplace" ? "mkt" : id;
    }

    Txt {
        text: "providers"
        size: 10
        color: Theme.muted
    }

    Repeater {
        model: pl.provs

        Row {
            id: prow

            required property var modelData
            readonly property string v: pl.rec && pl.rec.providers ? (pl.rec.providers[modelData.id] || "") : ""

            visible: v !== ""
            spacing: 4

            Txt {
                text: pl.short(prow.modelData.id)
                size: 10
                color: Theme.textSecondary
            }

            Glyph {
                visible: prow.v !== "unknown"
                outcome: prow.v
                size: 11
            }

            Txt {
                visible: prow.modelData.tier === "unsigned" || prow.modelData.verification !== "sigstore"
                text: prow.modelData.tier === "unsigned" ? "unsigned" : "dev"
                size: 10
                color: Theme.muted
            }
        }
    }
}
