pragma ComponentBehavior: Bound

import QtQuick

// 16:9 preview from the image cache; initials tile (accent colour) when the plugin has no
// decodable preview (mockup `.thumb` / `.ini`).
Rectangle {
    id: th

    property string url: ""
    property string ini: "?"
    property string accent: "blue"
    property bool small: false
    property int iniSize: small ? 12 : 22
    property bool hint: !small
    readonly property string src: ImageCache.version >= 0 ? ImageCache.path(url) : ""
    readonly property bool ok: img.status === Image.Ready

    color: Theme.bgDeep
    clip: true

    Rectangle {
        anchors.fill: parent
        visible: !th.ok
        color: Theme.c(th.accent)

        Txt {
            anchors.centerIn: parent
            text: th.ini
            size: th.iniSize
            weight: Font.Bold
            color: Theme.bgDeep
        }

        Txt {
            visible: th.hint && th.url === ""
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: 6
            anchors.bottomMargin: 3
            text: "NO PREVIEW"
            size: 9
            weight: Font.Medium
            color: Qt.alpha(Theme.bgDeep, 0.7)
            font.letterSpacing: 0.8
        }
    }

    Image {
        id: img

        anchors.fill: parent
        source: th.src
        asynchronous: true
        cache: true
        fillMode: Image.PreserveAspectCrop
        verticalAlignment: Image.AlignTop
        sourceSize.width: Math.ceil(th.width * 1.5)
        visible: th.ok
    }
}
