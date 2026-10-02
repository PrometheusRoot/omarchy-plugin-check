pragma ComponentBehavior: Bound

import QtQuick

// Four stat cells (mockup `.stat`): value + uppercase label on the deep background.
Row {
    id: sr

    property var cells: []

    spacing: 6

    Repeater {
        model: sr.cells

        Rectangle {
            id: cell

            required property var modelData

            width: (sr.width - 3 * sr.spacing) / 4
            height: 44
            color: Theme.bgDeep
            border.color: Theme.borderSubtle
            border.width: 1

            Column {
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 20
                spacing: 3

                Txt {
                    width: parent.width
                    text: cell.modelData[0]
                    size: 13
                    weight: Font.DemiBold
                }

                Txt {
                    width: parent.width
                    text: String(cell.modelData[1]).toUpperCase()
                    size: 9
                    color: Theme.muted
                    font.letterSpacing: 0.8
                }
            }
        }
    }
}
