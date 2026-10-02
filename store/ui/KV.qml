pragma ComponentBehavior: Bound

import QtQuick

// Definition list (mockup `.kv`): uppercase tracked keys, values; pairs = [[k, v, color?]].
Grid {
    id: kv

    property var pairs: []
    property int size: 11
    property int keyWidth: 90

    columns: 2
    columnSpacing: 14
    rowSpacing: 5
    width: parent ? parent.width : 0

    Repeater {
        model: kv.pairs.length * 2

        Txt {
            required property int index
            readonly property var p: kv.pairs[Math.floor(index / 2)]
            readonly property bool isKey: index % 2 === 0

            width: isKey ? kv.keyWidth : kv.width - kv.keyWidth - kv.columnSpacing
            text: isKey ? String(p[0]).toUpperCase() : String(p[1])
            size: isKey ? 10 : kv.size
            weight: isKey ? Font.Medium : Font.Normal
            color: isKey ? Theme.muted : p[2] ? Theme.c(p[2]) : Theme.text
            font.letterSpacing: isKey ? 1 : 0
            wrapMode: isKey ? Text.NoWrap : Text.Wrap
            elide: isKey ? Text.ElideRight : Text.ElideNone
            verticalAlignment: Text.AlignTop
        }
    }
}
