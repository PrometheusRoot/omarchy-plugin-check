pragma ComponentBehavior: Bound

import QtQuick

// Home before the catalog is there (lib/firstrun.mjs view): verifying / getting the catalog
// with a moving bar, or a friendly failure with retry. Never a stack trace (ADR-0042).
Column {
    id: fr

    readonly property var v: Store.frView
    readonly property bool failed: Store.fr.state === "failed"

    spacing: 14

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 10

        Mark {
            cell: 2.2
            anchors.verticalCenter: parent.verticalCenter
        }

        Txt {
            text: "omarchy-store"
            size: 18
            weight: Font.DemiBold
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 8

        Ico {
            name: fr.failed ? "alert" : "sig"
            size: 14
            color: fr.failed ? Theme.yellow : Theme.green
            anchors.verticalCenter: parent.verticalCenter
        }

        Txt {
            text: fr.v.title || (Store.verifyError !== "" ? "snapshot refused" : "loading…")
            size: 14
            weight: Font.Medium
            color: fr.failed ? Theme.yellow : Theme.text
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Txt {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: fr.v.detail || Store.verifyError
        size: 11
        color: Theme.textSecondary
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }

    // Indeterminate progress: a block sliding along a 1px track (zero radius, theme colours).
    Rectangle {
        visible: fr.v.busy
        anchors.horizontalCenter: parent.horizontalCenter
        width: 240
        height: 3
        color: Theme.borderSubtle
        clip: true

        Rectangle {
            id: slider

            width: 60
            height: parent.height
            color: Theme.brand

            SequentialAnimation on x {
                running: fr.visible && fr.v.busy
                loops: Animation.Infinite

                NumberAnimation {
                    from: -60
                    to: 240
                    duration: 1100
                    easing.type: Easing.InOutQuad
                }
            }
        }
    }

    Btn {
        visible: fr.v.retry
        anchors.horizontalCenter: parent.horizontalCenter
        kind: "primary"
        icon: "up"
        label: "retry"
        onClicked: Store.retry()
    }

    Txt {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: "independent community project · not affiliated with Omarchy"
        size: 10
        color: Theme.muted
    }
}
