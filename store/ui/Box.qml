pragma ComponentBehavior: Bound

import QtQuick

// Bordered surface box with an icon title (mockup `.aside-box` / `.sect`).
Rectangle {
    id: box

    property string title: ""
    property string icon: ""
    property string note: ""
    property int titleSize: 11
    default property alias content: inner.data
    property alias spacing: inner.spacing

    implicitHeight: inner.implicitHeight + head.height + 26
    color: Theme.surface
    border.color: Theme.borderSubtle
    border.width: 1

    Row {
        id: head

        x: 14
        y: 12
        height: 16
        spacing: 7
        visible: box.title !== ""

        Ico {
            name: box.icon
            size: 12
            color: Theme.text
            anchors.verticalCenter: parent.verticalCenter
        }

        Txt {
            text: box.title
            size: box.titleSize
            weight: Font.DemiBold
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Txt {
        visible: box.note !== ""
        anchors.right: parent.right
        anchors.rightMargin: 14
        y: 12
        height: 16
        text: box.note
        size: 10
        color: Theme.muted
    }

    Column {
        id: inner

        x: 14
        y: head.visible ? 36 : 12
        width: box.width - 28
        spacing: 8
    }
}
