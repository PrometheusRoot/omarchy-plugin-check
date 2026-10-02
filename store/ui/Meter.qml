pragma ComponentBehavior: Bound

import QtQuick

// Score meter (mockup `.meter`): 100px bar in the outcome colour + value.
Row {
    id: m

    property real value: 0
    property color tint: Theme.textSecondary

    spacing: 8

    Rectangle {
        width: 100
        height: 6
        anchors.verticalCenter: parent.verticalCenter
        color: Qt.alpha(m.tint, 0.22)

        Rectangle {
            width: Math.max(0, Math.min(1, m.value / 100)) * parent.width
            height: parent.height
            color: m.tint
        }
    }

    Txt {
        text: String(Math.round(m.value))
        size: 11
        weight: Font.Medium
    }
}
