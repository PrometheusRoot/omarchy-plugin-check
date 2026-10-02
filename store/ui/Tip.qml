pragma ComponentBehavior: Bound

import QtQuick

// Tooltip under (or right-aligned to) its parent; mockup `.tip::after`. Built only while
// shown: hundreds of glyphs and chips carry one, so the body is a lazy Loader.
Loader {
    id: tip

    property bool shown: false
    property string label: ""
    property bool alignRight: false

    active: shown && label !== ""
    z: 100
    x: alignRight ? (parent ? parent.width - width : 0) : 0
    y: parent ? parent.height + 6 : 0

    sourceComponent: Rectangle {
        width: Math.min(280, Math.max(140, body.implicitWidth + 16))
        height: body.implicitHeight + 10
        color: Theme.bgDeep
        border.color: Theme.borderStrong
        border.width: 1

        Txt {
            id: body

            x: 8
            y: 5
            width: Math.min(264, implicitWidth)
            size: 11
            text: tip.label
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
            lineHeight: 1.2
        }
    }
}
