pragma ComponentBehavior: Bound

import QtQuick

// Chip family (mockup `.chip`): outcome tones, brand/blue, hard-fail, criteria pass/fail/na,
// pressed filter chips. 22px high (18/20 for the small variants), 1px border, zero radius.
Rectangle {
    id: chip

    property string label: ""
    property string icon: ""
    property string count: ""
    // "" | safe caution risky blocked unreviewed stale | brand blue hf dim | pass fail na
    property string tone: ""
    property bool pressed: false
    property bool clickable: false
    property bool small: false
    property string tipText: ""

    signal clicked

    readonly property color toneColor: {
        switch (tone) {
        case "safe":
        case "pass":
            return Theme.green;
        case "caution":
            return Theme.yellow;
        case "risky":
            return Theme.orange;
        case "blocked":
        case "fail":
        case "hf":
            return Theme.red;
        case "stale":
        case "blue":
            return Theme.blue;
        case "brand":
            return Theme.brand;
        case "unreviewed":
        case "dim":
        case "na":
            return Theme.muted;
        default:
            return Theme.textSecondary;
        }
    }
    readonly property bool hot: mouse.containsMouse && clickable

    implicitHeight: small ? 20 : 22
    implicitWidth: row.implicitWidth + (small ? 10 : 14)
    opacity: tone === "na" ? 0.7 : 1
    color: pressed ? Theme.surface2 : (tone === "hf" || tone === "pass") ? Qt.alpha(toneColor, 0.12) : "transparent"
    border.width: 1
    border.color: pressed ? Theme.textSecondary : (tone === "" || tone === "unreviewed" || tone === "dim" || tone === "na") ? (hot ? Theme.textSecondary : Theme.borderStrong) : toneColor

    Row {
        id: row

        anchors.centerIn: parent
        spacing: 5

        Ico {
            visible: chip.icon !== ""
            name: chip.icon
            size: chip.small ? 11 : 12
            color: lbl.color
            anchors.verticalCenter: parent.verticalCenter
        }

        Txt {
            id: lbl

            anchors.verticalCenter: parent.verticalCenter
            text: chip.label
            size: chip.small ? 10 : 11
            weight: Font.Medium
            color: chip.pressed || chip.hot ? Theme.text : chip.toneColor
        }

        Txt {
            visible: chip.count !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: chip.count
            size: chip.small ? 10 : 11
            color: Theme.muted
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        enabled: chip.clickable || chip.tipText !== ""
        cursorShape: chip.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (chip.clickable)
            chip.clicked()
    }

    Tip {
        shown: mouse.containsMouse
        label: chip.tipText
    }
}
