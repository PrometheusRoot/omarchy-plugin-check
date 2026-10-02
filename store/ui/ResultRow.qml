pragma ComponentBehavior: Bound

import QtQuick
import "../lib/format.mjs" as F

// Search result row (mockup `.srow`): 72px thumb, highlighted name + author · description,
// kind/cat, stars, rank, verdict glyph.
Rectangle {
    id: row

    property var rec: ({})
    property bool current: false
    readonly property bool hot: mouse.containsMouse
    readonly property bool isInstalled: Installer.installedVersion >= 0 && !!Installer.installed[rec.id]
    readonly property string mark: Theme.mark.toString()

    signal activated

    height: 54
    color: current ? Theme.surface2 : hot ? Theme.surface : "transparent"

    Rectangle {
        visible: row.current
        width: 2
        height: parent.height
        color: Theme.brand
    }

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Theme.borderSubtle
    }

    Thumb {
        x: 8
        anchors.verticalCenter: parent.verticalCenter
        width: 72
        height: 40
        small: true
        url: row.rec.thumb || ""
        ini: row.rec.ini || "?"
        accent: F.accentFor(row.rec.id || "", row.rec.accent)
    }

    Column {
        x: 92
        anchors.verticalCenter: parent.verticalCenter
        width: row.width - 92 - 290
        spacing: 2

        Row {
            spacing: 6
            width: parent.width

            Txt {
                width: Math.min(implicitWidth, parent.width - 80)
                textFormat: Text.RichText
                clip: true
                text: F.highlight(row.rec.name, Store.words, row.mark)
                weight: Font.DemiBold
                size: 12
            }

            Chip {
                visible: row.isInstalled
                tone: "brand"
                label: "installed"
                small: true
                height: 16
            }
        }

        Txt {
            width: parent.width
            textFormat: Text.RichText
            clip: true
            text: F.highlight(row.rec.author, Store.words, row.mark) + " · " + F.highlight(F.clampText(row.rec.desc, 160), Store.words, row.mark)
            size: 10
            color: Theme.muted
        }
    }

    Column {
        x: row.width - 280
        width: 120
        anchors.verticalCenter: parent.verticalCenter

        Txt {
            width: parent.width
            text: row.rec.kind || ""
            size: 10
            color: Theme.muted
        }

        Txt {
            width: parent.width
            text: row.rec.cat || ""
            size: 10
            color: Theme.muted
        }
    }

    Row {
        x: row.width - 150
        width: 70
        layoutDirection: Qt.RightToLeft
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        Txt {
            text: F.int(row.rec.stars)
            size: 11
            color: Theme.textSecondary
        }

        Ico {
            name: "star"
            size: 11
        }
    }

    Txt {
        x: row.width - 70
        width: 40
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        text: row.rec.rank ? "#" + row.rec.rank : "—"
        size: 10
        color: Theme.muted
    }

    Glyph {
        x: row.width - 28
        anchors.verticalCenter: parent.verticalCenter
        outcome: row.rec.verdict || "unreviewed"
        size: 13
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.activated()
    }
}
