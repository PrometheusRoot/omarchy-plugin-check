pragma ComponentBehavior: Bound

import QtQuick

// All text in the store is mono (approved mockup): JetBrainsMono Nerd Font.
Text {
    property int size: 12
    property int weight: Font.Normal

    color: Theme.text
    font.family: Theme.font
    font.pixelSize: size
    font.weight: weight
    elide: Text.ElideRight
    verticalAlignment: Text.AlignVCenter
    textFormat: Text.PlainText
}
