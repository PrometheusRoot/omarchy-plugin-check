pragma ComponentBehavior: Bound

import QtQuick

// Button family (mockup `.btn`): primary (brand fill), caution, risky, danger, ghost; sm.
// Disabled = 50% opacity + dashed-looking muted border, with an explanatory tooltip.
Rectangle {
    id: btn

    property string label: ""
    property string icon: ""
    property string key: ""
    property string kind: "" // "" primary caution risky danger ghost
    property bool sm: false
    property bool enabledState: true
    property string tipText: ""
    property bool tipRight: false
    property bool focused: false

    signal clicked

    readonly property bool hot: mouse.containsMouse && enabledState
    readonly property color fg: {
        if (kind === "primary")
            return Theme.bgDeep;
        if (kind === "caution")
            return Theme.yellow;
        if (kind === "risky")
            return Theme.orange;
        if (kind === "danger")
            return Theme.red;
        return hot ? Theme.text : Theme.textSecondary;
    }

    implicitHeight: sm ? 24 : 30
    implicitWidth: row.implicitWidth + (sm ? 16 : 24)
    opacity: enabledState ? (kind === "primary" && hot ? 0.92 : 1) : 0.5
    color: kind === "primary" ? Theme.brand : kind === "ghost" ? "transparent" : Theme.surface
    border.width: focused ? 2 : 1
    border.color: focused ? Theme.blue : kind === "primary" ? Theme.brand : kind === "caution" ? Theme.yellow : kind === "risky" ? Theme.orange : kind === "danger" ? Theme.red : hot ? Theme.textSecondary : Theme.borderStrong

    Row {
        id: row

        anchors.centerIn: parent
        spacing: 7

        Ico {
            visible: btn.icon !== ""
            name: btn.icon
            size: btn.sm ? 12 : 14
            color: btn.fg
            anchors.verticalCenter: parent.verticalCenter
        }

        Txt {
            anchors.verticalCenter: parent.verticalCenter
            text: btn.label
            size: btn.sm ? 11 : 12
            weight: Font.Medium
            color: btn.fg
        }

        Kbd {
            visible: btn.key !== ""
            anchors.verticalCenter: parent.verticalCenter
            label: btn.key
            opacity: 0.7
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: btn.enabledState ? Qt.PointingHandCursor : Qt.ForbiddenCursor
        onClicked: if (btn.enabledState)
            btn.clicked()
    }

    Tip {
        shown: mouse.containsMouse
        label: btn.tipText
        alignRight: btn.tipRight
    }
}
