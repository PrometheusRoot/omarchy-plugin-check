pragma ComponentBehavior: Bound

import QtQuick
import "../lib/format.mjs" as F

// Hero carousel (mockup `.hero`): preview image left (fades into the text panel), text
// panel 420px right; dots + h/l hint bottom-left, prev/next bottom-right of the image.
Rectangle {
    id: hero

    property var items: []
    property int index: 0
    property bool focusedHero: false
    readonly property var rec: items.length ? items[Math.min(index, items.length - 1)] : null

    signal open(var rec)
    signal step(int d)
    signal pick(int i)

    height: 300
    color: Theme.surface
    visible: rec !== null

    Item {
        id: imgBox

        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: txt.left
        clip: true

        Thumb {
            anchors.fill: parent
            url: hero.rec ? (hero.rec.full || hero.rec.thumb) : ""
            ini: hero.rec ? hero.rec.ini : ""
            accent: hero.rec ? F.accentFor(hero.rec.id, hero.rec.accent) : "blue"
            iniSize: 64
        }

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal

                GradientStop {
                    position: 0.6
                    color: Qt.alpha(Theme.surface, 0)
                }

                GradientStop {
                    position: 1
                    color: Theme.surface
                }
            }
        }

        Row {
            x: 16
            y: 14
            spacing: 6

            Chip {
                tone: "brand"
                icon: "star"
                label: "featured"
                color: Theme.bgDeep
            }

            Chip {
                label: hero.rec ? hero.rec.cat : ""
                color: Theme.bgDeep
            }
        }

        Row {
            x: 16
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 12
            spacing: 4

            Repeater {
                model: hero.items.length

                Rectangle {
                    required property int index

                    width: 18
                    height: 4
                    anchors.verticalCenter: parent.verticalCenter
                    color: index === hero.index ? Theme.brand : Theme.borderStrong

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -4
                        cursorShape: Qt.PointingHandCursor
                        onClicked: hero.pick(parent.index)
                    }
                }
            }

            Item {
                width: 6
                height: 1
            }

            Kbd {
                label: "h"
            }

            Kbd {
                label: "l"
            }
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 12
            spacing: 4

            Repeater {
                model: [["left", -1], ["right", 1]]

                Rectangle {
                    id: navBtn

                    required property var modelData

                    width: 26
                    height: 22
                    color: Theme.bgDeep
                    border.width: 1
                    border.color: navMouse.containsMouse ? Theme.textSecondary : Theme.borderStrong

                    Ico {
                        anchors.centerIn: parent
                        name: navBtn.modelData[0]
                        size: 13
                        color: navMouse.containsMouse ? Theme.text : Theme.textSecondary
                    }

                    MouseArea {
                        id: navMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: hero.step(navBtn.modelData[1])
                    }
                }
            }
        }
    }

    Item {
        id: txt

        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 420

        Column {
            x: 24
            y: 22
            width: 372
            spacing: 10

            Row {
                spacing: 10

                Txt {
                    text: hero.rec ? hero.rec.author : ""
                    size: 11
                    color: Theme.muted
                }

                Txt {
                    text: "·  " + (hero.rec ? hero.rec.kind : "")
                    size: 11
                    color: Theme.muted
                }

                Txt {
                    visible: hero.rec && hero.rec.verif === "verified"
                    text: "·  verified"
                    size: 11
                    color: Theme.green
                }
            }

            Txt {
                width: 372
                text: hero.rec ? hero.rec.name : ""
                size: 24
                weight: Font.DemiBold
                font.letterSpacing: -0.7
            }

            Txt {
                width: 372
                height: 54
                text: hero.rec ? hero.rec.desc : ""
                size: 12
                color: Theme.textSecondary
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                lineHeight: 1.15
                verticalAlignment: Text.AlignTop
            }

            Row {
                spacing: 12

                Row {
                    spacing: 4

                    Ico {
                        name: "star"
                        size: 12
                        color: Theme.text
                    }

                    Txt {
                        text: F.int(hero.rec ? hero.rec.stars : 0)
                        size: 11
                        weight: Font.DemiBold
                    }
                }

                Row {
                    spacing: 4

                    Ico {
                        name: "rank"
                        size: 12
                        color: Theme.muted
                    }

                    Txt {
                        text: hero.rec && hero.rec.rank ? "#" + hero.rec.rank : "—"
                        size: 11
                        color: Theme.muted
                    }
                }

                Row {
                    spacing: 4

                    Glyph {
                        outcome: hero.rec ? hero.rec.verdict : "unreviewed"
                        size: 12
                    }

                    Txt {
                        text: hero.rec ? hero.rec.verdict : ""
                        size: 11
                        color: Theme.c(F.outcome(hero.rec ? hero.rec.verdict : "").color)
                    }

                    Txt {
                        visible: hero.rec && hero.rec.risk !== null && hero.rec.risk !== undefined
                        text: hero.rec ? hero.rec.risk + "/100" : ""
                        size: 11
                        color: Theme.muted
                    }
                }

                Txt {
                    text: "updated " + F.ago(hero.rec ? hero.rec.updated : "", Date.now())
                    size: 11
                    color: Theme.muted
                }
            }

            CritChips {
                width: 372
                criteria: hero.rec ? hero.rec.criteria : null
                keys: F.CRITERIA.slice(0, 5)
            }

            ProviderLine {
                rec: hero.rec
            }
        }

        Row {
            x: 24
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 18
            spacing: 8

            InstallButton {
                rec: hero.rec || ({})
            }

            Btn {
                kind: "ghost"
                label: "details"
                key: "⏎"
                focused: hero.focusedHero
                onClicked: hero.open(hero.rec)
            }
        }
    }
}
