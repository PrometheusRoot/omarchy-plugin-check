pragma ComponentBehavior: Bound

import QtQuick
import "../lib/format.mjs" as F

// Compact table (mockup `.tbl`): uppercase header, 1px rules; `chipCol` renders that
// column as a chip (severity / ecosystem).
Column {
    id: tbl

    property var head: []
    property var widths: []
    property var rows: []
    property int chipCol: -1

    Item {
        width: tbl.width
        height: 22

        Row {
            anchors.verticalCenter: parent.verticalCenter

            Repeater {
                model: tbl.head

                Txt {
                    required property string modelData
                    required property int index

                    width: tbl.widths[index] || 80
                    leftPadding: 6
                    text: modelData.toUpperCase()
                    size: 10
                    color: Theme.muted
                    font.letterSpacing: 1
                }
            }
        }

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Theme.borderStrong
        }
    }

    Repeater {
        model: tbl.rows

        Item {
            id: tr

            required property var modelData

            width: tbl.width
            height: Math.max(28, cells.implicitHeight + 10)

            Row {
                id: cells

                anchors.verticalCenter: parent.verticalCenter

                Repeater {
                    model: tr.modelData

                    Item {
                        id: cell

                        required property string modelData
                        required property int index

                        width: tbl.widths[index] || 80
                        height: Math.max(chip.visible ? 18 : 0, txt.visible ? txt.implicitHeight : 0)

                        Chip {
                            id: chip

                            visible: cell.index === tbl.chipCol && cell.modelData !== "" && cell.modelData !== "—"
                            x: 6
                            small: true
                            height: 18
                            label: cell.modelData
                            tone: F.sevOutcome(cell.modelData)
                        }

                        Txt {
                            id: txt

                            visible: !chip.visible
                            x: 6
                            width: parent.width - 12
                            text: cell.modelData
                            size: 11
                            color: cell.index === tbl.head.length - 1 ? Theme.muted : Theme.text
                            wrapMode: cell.index === 1 ? Text.Wrap : Text.NoWrap
                            elide: cell.index === 1 ? Text.ElideNone : Text.ElideRight
                        }
                    }
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Theme.borderSubtle
            }
        }
    }
}
