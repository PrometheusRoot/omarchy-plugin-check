pragma ComponentBehavior: Bound

import QtQuick
import "../lib/format.mjs" as F

// App header (mockup `.hdr`): mark + "omarchy-store" over the not-affiliated notice, tabs
// with key caps, search field with live latency, snapshot age chip.
Rectangle {
    id: hdr

    property alias input: field

    Connections {
        target: Store

        function onQueryChanged() {
            if (field.text !== Store.query)
                field.text = Store.query;
        }
    }

    height: 44
    color: Theme.bgDeep

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Theme.borderSubtle
    }

    Row {
        x: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        Row {
            spacing: 8
            rightPadding: 8
            anchors.verticalCenter: parent.verticalCenter

            Mark {
                anchors.verticalCenter: parent.verticalCenter
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                Txt {
                    text: "omarchy-store"
                    size: 13
                    weight: Font.DemiBold
                    font.letterSpacing: -0.3
                }

                Txt {
                    text: "community · not affiliated with Omarchy"
                    size: 8
                    color: Theme.muted
                }
            }
        }

        Repeater {
            model: [["home", "home", "1"], ["search", "search", "2"], ["browse", "grid", "3"], ["installed", "dl", "4"], ["status", "snap", "5"]]

            Rectangle {
                id: tabBtn

                required property var modelData
                readonly property bool on: Store.tab === modelData[0] || (Store.tab === "detail" && Store.prevTab === modelData[0])

                height: 30
                width: tabRow.implicitWidth + 20
                anchors.verticalCenter: parent.verticalCenter
                color: on ? Theme.surface2 : tabMouse.containsMouse ? Theme.surface : "transparent"
                border.width: 1
                border.color: on ? Theme.borderStrong : "transparent"

                Row {
                    id: tabRow

                    anchors.centerIn: parent
                    spacing: 7

                    Ico {
                        name: tabBtn.modelData[1]
                        size: 12
                        color: tabBtn.on || tabMouse.containsMouse ? Theme.text : Theme.textSecondary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Txt {
                        text: tabBtn.modelData[0]
                        size: 12
                        weight: Font.Medium
                        color: tabBtn.on || tabMouse.containsMouse ? Theme.text : Theme.textSecondary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Txt {
                        visible: tabBtn.modelData[0] === "installed"
                        text: String(Store.installedRows.length)
                        size: 10
                        color: Theme.muted
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Kbd {
                        label: tabBtn.modelData[2]
                        opacity: tabBtn.on ? 0.9 : 0.6
                        fg: tabBtn.on ? Theme.brand : Theme.textSecondary
                        edge: tabBtn.on ? Theme.brand : Theme.borderStrong
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: tabMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Store.go(tabBtn.modelData[0])
                }
            }
        }
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        Rectangle {
            width: 300
            height: 30
            color: Theme.surface
            border.width: 1
            border.color: field.activeFocus ? Theme.brand : Theme.borderStrong

            Ico {
                id: sIcon

                x: 8
                anchors.verticalCenter: parent.verticalCenter
                name: "search"
                size: 12
                color: field.activeFocus ? Theme.textSecondary : Theme.muted
            }

            TextInput {
                id: field

                anchors.left: sIcon.right
                anchors.leftMargin: 7
                anchors.right: lat.left
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.text
                selectionColor: Theme.surface2
                font.family: Theme.font
                font.pixelSize: 12
                clip: true
                onTextEdited: Store.setQuery(text)
                onActiveFocusChanged: {
                    Store.searchFocused = activeFocus;
                    if (activeFocus && Store.tab !== "search" && Store.tab !== "detail")
                        Store.go("search");
                }

                Txt {
                    visible: field.text === ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: "search " + F.int(Store.total) + " plugins"
                    size: 12
                    color: Theme.muted
                }
            }

            Item {
                id: lat

                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: Store.shownSeq > 0 && Store.query !== "" ? latText.implicitWidth : slash.width
                height: 16

                Txt {
                    id: latText

                    visible: Store.shownSeq > 0 && Store.query !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: F.int(Store.resultCount) + " · " + F.ms(Store.resultMs) + " ms"
                    size: 10
                    color: Theme.muted
                }

                Kbd {
                    id: slash

                    visible: !latText.visible
                    label: "/"
                }
            }
        }

        Rectangle {
            width: snapRow.implicitWidth + 12
            height: 30
            color: "transparent"

            Row {
                id: snapRow

                anchors.centerIn: parent
                spacing: 5

                Ico {
                    name: (Store.usingDev || Store.meta.dev) ? "unsig" : "sig"
                    size: 12
                    color: (Store.usingDev || Store.meta.dev) ? Theme.yellow : Theme.green
                    anchors.verticalCenter: parent.verticalCenter
                }

                Txt {
                    text: (Store.usingDev || Store.meta.dev) ? "dev" : F.ago(Store.meta.generatedAt, Date.now())
                    size: 11
                    color: (Store.usingDev || Store.meta.dev) ? Theme.yellow : Theme.green
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            HoverHandler {
                id: snapHover
            }

            Tip {
                shown: snapHover.hovered
                alignRight: true
                label: ((Store.usingDev || Store.meta.dev) ? "dev snapshot · unsigned\n" : "signed snapshot\n") + "catalog " + F.dateOnly(Store.meta.catalogAt) + " · " + F.int(Store.total) + " plugins\nproviders: " + (Store.meta.providers || []).map(p => p.id + " " + p.tier).join(", ")
            }
        }
    }
}
