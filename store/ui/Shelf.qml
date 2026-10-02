pragma ComponentBehavior: Bound

import QtQuick

// Horizontal shelf (mockup `.shelf` + `.rail`): header with icon, title, why-line and
// "see all ›", then a recycling ListView of cards.
Column {
    id: shelf

    property string title: ""
    property string icon: ""
    property string why: ""
    property string key: ""
    property string extra: ""
    property var items: []
    property int cursor: -1 // focused card, -1 = none
    // Cards are only built once the shelf is near the viewport (cold start: the first frame
    // pays for what it shows). Latches on.
    property bool near: true
    property bool live: false

    onNearChanged: if (near)
        live = true
    Component.onCompleted: if (near)
        live = true

    signal open(var rec)

    width: parent ? parent.width : 0
    topPadding: 14
    bottomPadding: 4
    visible: items.length > 0

    function reveal(i) {
        rail.positionViewAtIndex(i, ListView.Contain);
    }

    Item {
        width: shelf.width
        height: 21

        Row {
            x: 20
            spacing: 10
            anchors.verticalCenter: parent.verticalCenter

            Row {
                spacing: 7

                Ico {
                    name: shelf.icon
                    size: 13
                    color: Theme.text
                    anchors.verticalCenter: parent.verticalCenter
                }

                Txt {
                    text: shelf.title
                    size: 13
                    weight: Font.DemiBold
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Txt {
                text: shelf.why
                size: 10
                color: Theme.muted
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Txt {
            anchors.right: parent.right
            anchors.rightMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            text: "see all ›"
            size: 11
            color: more.containsMouse ? Theme.text : Theme.muted

            MouseArea {
                id: more

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Store.seeAll(shelf.key)
            }
        }
    }

    Item {
        width: 1
        height: 8
    }

    ListView {
        id: rail

        width: shelf.width
        height: 176
        orientation: ListView.Horizontal
        spacing: 10
        leftMargin: 20
        rightMargin: 20
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        cacheBuffer: 200
        model: shelf.live ? shelf.items : []

        delegate: Card {
            required property var modelData
            required property int index

            rec: modelData
            extra: shelf.extra
            current: index === shelf.cursor
            onActivated: shelf.open(modelData)
        }
    }
}
