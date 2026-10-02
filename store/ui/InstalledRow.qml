pragma ComponentBehavior: Bound

import QtQuick

// One installed plugin (mockup `.irw`).
Rectangle {
    id: row

    property var rec: ({})
    property bool current: false
    readonly property var entry: Installer.installedVersion >= 0 ? Installer.installed[rec.id] || ({}) : ({})
    readonly property string st: Installer.installedVersion >= 0 ? Installer.stateOf(rec) : ""
    readonly property string reviewed: rec.commit ? String(rec.commit).slice(0, 7) : ""
    readonly property real c1: width * 0.36

    height: 52
    color: current ? Theme.surface2 : mouse.containsMouse ? Theme.surface : "transparent"

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

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Store.open(row.rec)
    }

    Glyph {
        x: 12
        anchors.verticalCenter: parent.verticalCenter
        outcome: row.rec.verdict || "unreviewed"
        size: 16
    }

    Column {
        x: 44
        width: row.c1 - 56
        anchors.verticalCenter: parent.verticalCenter

        Txt {
            width: parent.width
            text: row.rec.name || ""
            weight: Font.DemiBold
        }

        Txt {
            width: parent.width
            text: (row.rec.id || "") + " · " + (row.rec.author || "")
            size: 10
            color: Theme.muted
        }
    }

    Column {
        x: row.c1
        width: 150
        anchors.verticalCenter: parent.verticalCenter

        Row {
            spacing: 6

            Txt {
                text: row.entry.sha ? String(row.entry.sha).slice(0, 7) : "—"
                size: 11
                color: Theme.textSecondary
            }

            Txt {
                text: !row.reviewed ? "no review" : row.st === "ok" ? "= reviewed" : "≠ " + row.reviewed
                size: 10
                color: Theme.muted
            }
        }

        Txt {
            visible: row.st === "update" && !!row.entry.upstream
            text: "upstream " + (row.entry.upstream || "")
            size: 10
            color: Theme.blue
        }
    }

    Chip {
        x: row.c1 + 160
        anchors.verticalCenter: parent.verticalCenter
        tone: row.st === "blocked" ? "blocked" : row.st === "update" ? "blue" : row.st === "stale" ? "stale" : row.st === "ok" ? "safe" : "unreviewed"
        icon: row.st === "blocked" ? "blocked" : row.st === "update" ? "up" : row.st === "stale" ? "stale" : row.st === "ok" ? "check" : "unreviewed"
        label: row.st === "update" ? "update available" : row.st === "ok" ? "up to date" : row.st === "unreviewed" || row.st === "unknown" ? "not reviewed" : row.st
    }

    Row {
        x: row.c1 + 300
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        Txt {
            text: (row.rec.verdict || "") + (row.rec.risk !== null && row.rec.risk !== undefined ? " " + row.rec.risk + "/100" : "")
            size: 11
            color: Theme.muted
        }

        ProviderLine {
            rec: row.rec
        }
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        Btn {
            visible: row.st === "update"
            sm: true
            icon: "up"
            label: "update"
            enabledState: Installer.canInstall
            tipText: Installer.why
            tipRight: true
            onClicked: Store.askInstall(row.rec, true)
        }

        Btn {
            visible: row.st === "stale"
            sm: true
            kind: "caution"
            icon: "stale"
            label: "roll back"
            enabledState: Installer.canInstall
            tipText: Installer.canInstall ? "installed commit has no review yet. keep (nothing changes) or roll back to the reviewed commit." : Installer.why
            tipRight: true
            onClicked: Store.askInstall(row.rec, true)
        }

        Btn {
            sm: true
            kind: row.st === "blocked" ? "danger" : "ghost"
            icon: "trash"
            label: "remove"
            onClicked: Store.askRemove(row.rec)
        }
    }
}
