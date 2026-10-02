pragma ComponentBehavior: Bound

import QtQuick
import "../lib/format.mjs" as F

// Category tile (mockup `.cat`): blue icon, lowercase name, count.
Rectangle {
    id: tile

    property string name: ""
    property int count: 0
    property bool current: false
    property string suffix: ""
    readonly property bool hot: mouse.containsMouse

    signal activated

    height: 64
    color: hot || current ? Theme.surface2 : Theme.surface
    border.width: current ? 2 : 1
    border.color: current ? Theme.brand : hot ? Theme.borderStrong : Theme.borderSubtle

    Row {
        x: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        Text {
            text: F.categoryIcon(tile.name)
            font.family: Theme.font
            font.pixelSize: 16
            color: Theme.blue
            anchors.verticalCenter: parent.verticalCenter
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter

            Txt {
                text: tile.name.toLowerCase()
                size: 12
                weight: Font.DemiBold
                width: Math.min(implicitWidth, tile.width - 44)
            }

            Txt {
                text: F.int(tile.count) + tile.suffix
                size: 10
                color: Theme.muted
            }
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: tile.activated()
    }
}
