pragma ComponentBehavior: Bound

import QtQuick
import "../lib/format.mjs" as F

// Plugin card = GridView/ListView delegate (mockup `.card`): 16:9 thumb with rank badge and
// verdict glyph, name, author, stars (+ trend / age), category, "installed" mark.
Rectangle {
    id: card

    property var rec: ({})
    property bool current: false
    property string extra: "" // "" trend new upd
    readonly property bool hot: mouse.containsMouse
    readonly property bool isInstalled: Installer.installedVersion >= 0 && !!Installer.installed[rec.id]

    signal activated

    width: 196
    height: thumb.height + body.height
    color: hot || current ? Theme.surface2 : Theme.surface
    border.width: current ? 2 : 1
    border.color: current ? Theme.brand : hot ? Theme.borderStrong : Theme.borderSubtle

    Thumb {
        id: thumb

        x: card.border.width
        y: card.border.width
        width: card.width - 2 * card.border.width
        height: Math.round((card.width - 2) * 9 / 16)
        url: card.rec.thumb || ""
        ini: card.rec.ini || "?"
        accent: F.accentFor(card.rec.id || "", card.rec.accent)

        Rectangle {
            visible: !!card.rec.rank
            height: 18
            width: rk.implicitWidth + 12
            color: Theme.bgDeep
            border.color: Theme.borderStrong
            border.width: 1

            Txt {
                id: rk

                anchors.centerIn: parent
                text: "#" + card.rec.rank
                size: 10
                weight: Font.DemiBold
                color: card.rec.rank <= 10 ? Theme.brand : Theme.text
            }
        }

        Rectangle {
            anchors.right: parent.right
            width: 22
            height: 18
            color: Theme.bgDeep
            border.color: Theme.borderStrong
            border.width: 1

            Glyph {
                anchors.centerIn: parent
                outcome: card.rec.verdict || "unreviewed"
                size: 12
            }
        }
    }

    Column {
        id: body

        anchors.top: thumb.bottom
        x: 9
        width: card.width - 18
        topPadding: 7
        bottomPadding: 8
        spacing: 3

        Txt {
            width: parent.width
            text: card.rec.name || ""
            weight: Font.DemiBold
            size: 12
        }

        Txt {
            width: parent.width - (card.isInstalled ? 70 : 0)
            text: card.rec.author || ""
            size: 10
            color: Theme.muted
        }

        Item {
            width: parent.width
            height: 16

            Row {
                spacing: 8
                anchors.verticalCenter: parent.verticalCenter

                Row {
                    spacing: 3

                    Ico {
                        name: "star"
                        size: 11
                    }

                    Txt {
                        text: F.int(card.rec.stars)
                        size: 10
                        color: Theme.textSecondary
                    }
                }

                Txt {
                    visible: card.extra === "trend"
                    text: "↑" + (card.rec.vel30 || 0)
                    size: 10
                    color: Theme.cyan
                }

                Txt {
                    visible: card.extra === "new" || card.extra === "upd"
                    text: F.ago(card.extra === "new" ? card.rec.listed : card.rec.updated, Date.now())
                    size: 10
                    color: Theme.muted
                }
            }

            Txt {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, 80)
                horizontalAlignment: Text.AlignRight
                text: card.rec.cat || ""
                size: 10
                color: Theme.muted
            }
        }
    }

    Txt {
        visible: card.isInstalled
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 30
        text: "INSTALLED"
        size: 9
        color: Theme.brand
        font.letterSpacing: 0.8
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: card.activated()
    }
}
