pragma ComponentBehavior: Bound

import QtQuick

// Key cap: 16px, 1px strong border, deep background (mockup `.kbd`).
Rectangle {
    id: k

    property string label: ""
    property color fg: Theme.textSecondary
    property color edge: Theme.borderStrong

    implicitWidth: Math.max(16, t.implicitWidth + 8)
    implicitHeight: 16
    color: Theme.bgDeep
    border.color: edge
    border.width: 1

    Txt {
        id: t

        anchors.centerIn: parent
        size: 10
        weight: Font.Medium
        color: k.fg
        text: k.label
    }
}
