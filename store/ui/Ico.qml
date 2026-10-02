pragma ComponentBehavior: Bound

import QtQuick
import "../lib/format.mjs" as F

// A Nerd Font glyph by name (lib/format.mjs ICON), sized like the mockup's svg icons.
Text {
    property string name: "dots"
    property int size: 14

    text: F.ICON[name] || ""
    color: Theme.textSecondary
    font.family: Theme.font
    font.pixelSize: size
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignHCenter
    textFormat: Text.PlainText
}
