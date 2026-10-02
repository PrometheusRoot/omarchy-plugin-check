pragma ComponentBehavior: Bound

import QtQuick
import "../lib/format.mjs" as F

// One provider report (mockup `.prow`): glyph, name + tier chip + date, criteria chips,
// signature. row = null renders "no provider yet".
Item {
    id: pr

    property var row: null
    property string listed: ""
    readonly property bool capped: row && (row.tier === "community" || row.tier === "unsigned")
    readonly property string shown: row ? (row.verdict === "unknown" ? "unreviewed" : row.verdict) : "unreviewed"

    height: 44

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.borderSubtle
    }

    Glyph {
        x: 0
        anchors.verticalCenter: parent.verticalCenter
        outcome: pr.shown
        size: 16
    }

    Column {
        x: 32
        width: 150
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Txt {
            width: parent.width
            text: pr.row ? pr.row.name : "no provider yet"
            weight: Font.DemiBold
        }

        Row {
            spacing: 5

            Chip {
                visible: !!pr.row
                small: true
                height: 18
                tone: pr.row && pr.row.tier === "core" ? "brand" : pr.row && pr.row.tier === "verified" ? "blue" : ""
                label: pr.row ? pr.row.tier + (pr.capped ? " ≤caution" : "") : ""
            }

            Txt {
                text: pr.row ? (pr.row.when || "") : "listed " + F.ago(pr.listed, Date.now()) + " ago"
                size: 10
                color: Theme.muted
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    Item {
        x: 192
        width: pr.width - 192 - 110
        height: parent.height

        CritChips {
            visible: !!pr.row && pr.row.tier !== "unsigned"
            width: parent.width
            anchors.verticalCenter: parent.verticalCenter
            criteria: pr.row ? {
                checked: pr.row.checked,
                failed: pr.row.failed
            } : null
            keys: F.CRITERIA.slice(0, 7)
        }

        Txt {
            visible: !pr.row || pr.row.tier === "unsigned"
            width: parent.width
            anchors.verticalCenter: parent.verticalCenter
            text: pr.row ? pr.row.summary : "new listings are scanned within 24–72 h · install asks for confirmation"
            size: 11
            color: Theme.muted
        }
    }

    Row {
        visible: !!pr.row
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3

        Ico {
            name: pr.row && pr.row.signed ? "sig" : "unsig"
            size: 12
            color: pr.row && pr.row.signed ? Theme.green : Theme.muted
        }

        Txt {
            text: pr.row ? (pr.row.signed ? "sig" : pr.row.verification) : ""
            size: 10
            color: pr.row && pr.row.signed ? Theme.green : Theme.muted
        }
    }
}
