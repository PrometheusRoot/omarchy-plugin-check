pragma ComponentBehavior: Bound

import QtQuick

// In-window dialog frame (mockup `.dlg`): header with glyph + title + esc, body, footer.
Rectangle {
    id: dlg

    property string title: ""
    property string glyph: ""
    property string outcome: ""
    property string footNote: ""
    default property alias content: bodyCol.data
    property alias buttons: btnRow.data

    width: 520
    height: head.height + bodyCol.implicitHeight + 28 + foot.height
    color: Theme.bg
    border.color: Theme.borderStrong
    border.width: 1

    // Swallow clicks so they never reach the scrim (which closes the dialog).
    MouseArea {
        anchors.fill: parent
    }

    Rectangle {
        id: head

        x: 1
        y: 1
        width: parent.width - 2
        height: 44
        color: Theme.bgDeep

        Row {
            x: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            Glyph {
                visible: dlg.outcome !== ""
                outcome: dlg.outcome || "unreviewed"
                size: 16
            }

            Ico {
                visible: dlg.outcome === "" && dlg.glyph !== ""
                name: dlg.glyph
                size: 16
                color: Theme.text
            }

            Txt {
                text: dlg.title
                size: 13
                weight: Font.DemiBold
                width: Math.min(implicitWidth, dlg.width - 100)
            }
        }

        Kbd {
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            label: "esc"
        }

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Theme.borderSubtle
        }
    }

    Column {
        id: bodyCol

        x: 16
        anchors.top: head.bottom
        anchors.topMargin: 14
        width: dlg.width - 32
        spacing: 10
    }

    Rectangle {
        id: foot

        anchors.bottom: parent.bottom
        anchors.bottomMargin: 1
        x: 1
        width: parent.width - 2
        height: 50
        color: "transparent"

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.borderSubtle
        }

        Txt {
            x: 15
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - btnRow.width - 40
            text: dlg.footNote
            size: 10
            color: Theme.muted
            wrapMode: Text.Wrap
            maximumLineCount: 2
        }

        Row {
            id: btnRow

            anchors.right: parent.right
            anchors.rightMargin: 15
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
        }
    }
}
