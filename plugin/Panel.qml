pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "lib/panel.mjs" as P

// omarchy-store verdict panel (kind "panel"; mockup "panel · Panel.qml"). Summoned by a right
// click on the bar shield (`omarchy-shell shell toggle io.github.prometheusroot.omarchy-store`).
// Reads the cached ~/.cache/omarchy-plugin-check/status.json (FileView, watched); never polls.
// Rescan runs `omarchy-plugin-check status --json` once; "store" opens the store window
// (store/bin/omarchy-store, single instance). Logic lives in lib/panel.mjs.
Item {
    id: root

    property var shell: null
    property var manifest: null

    property bool opened: false
    property bool scanning: false
    property var status: null
    property string statusError: ""
    property var pal: P.palette("")
    property real now: Date.now() / 1000
    property int cursor: -1

    readonly property string home: Quickshell.env("HOME")
    readonly property string bin: P.cliPath(Qt.resolvedUrl("."))
    readonly property var storeArgv: P.storeArgv(Qt.resolvedUrl("."))
    readonly property var worst: P.worst(status)
    readonly property var rows: P.rows(status)
    readonly property var badge: P.snapshotBadge(status, now)
    // why: Style.font is declared as a plain QtObject, so qmllint cannot see its members.
    readonly property var type: Style.font
    readonly property string mono: type.family
    readonly property color fg: pal.fg
    readonly property color dim: Qt.alpha(pal.fg, 0.55)
    readonly property color line: Qt.alpha(pal.fg, 0.12)

    function open(payloadJson) {
        now = Date.now() / 1000;
        cursor = -1;
        opened = true;
        statusFile.reload();
        Qt.callLater(function () {
            if (root.opened)
                keys.forceActiveFocus();
        });
    }

    // Host-initiated close (`shell hide`).
    function close() {
        opened = false;
    }

    // User-initiated close: tell the host so its open state and `toggle` stay right.
    function dismiss() {
        if (shell && typeof shell.hide === "function")
            shell.hide((manifest && manifest.id) || P.PLUGIN_ID);
        else
            close();
    }

    function rescan() {
        const argv = P.rescanArgv(bin);
        if (!argv || scanProc.running)
            return;
        scanning = true;
        scanProc.command = argv;
        scanProc.running = true;
    }

    function run(argv) {
        if (argv)
            Quickshell.execDetached(argv);
    }

    function openStore() {
        run(storeArgv);
        dismiss();
    }

    function openCard(row) {
        run(P.cardArgv(bin, row.id));
        dismiss();
    }

    FileView {
        id: statusFile

        path: root.home + "/.cache/omarchy-plugin-check/status.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const r = P.parseStatus(text());
            root.status = r.doc;
            root.statusError = r.error;
            root.now = Date.now() / 1000;
        }
        onLoadFailed: {
            root.status = null;
            root.statusError = "no status yet";
            // First open on this machine: one scan, then the watch takes over.
            root.rescan();
        }
    }

    FileView {
        path: root.home + "/.local/state/omarchy/current/theme/colors.toml"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.pal = P.palette(text())
    }

    Process {
        id: scanProc

        stdout: StdioCollector {}
        onExited: {
            root.scanning = false;
            statusFile.reload();
        }
    }

    PanelWindow {
        id: win

        visible: root.opened
        color: "transparent"
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0
        implicitWidth: 380
        implicitHeight: body.implicitHeight + 2
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "omarchy-plugin-check"
        WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        anchors {
            top: true
            right: true
        }

        margins {
            top: Style.gapsOut
            right: Style.gapsOut
        }

        Rectangle {
            anchors.fill: parent
            color: root.pal.bg
            border.color: root.line
            border.width: 1

            Item {
                id: keys

                focus: true
                Keys.onEscapePressed: root.dismiss()
                Keys.onPressed: function (e) {
                    if (e.text === "r")
                        root.rescan();
                    else if (e.text === "s")
                        root.openStore();
                    else if (e.key === Qt.Key_J || e.key === Qt.Key_Down)
                        root.cursor = Math.min(root.rows.length - 1, root.cursor + 1);
                    else if (e.key === Qt.Key_K || e.key === Qt.Key_Up)
                        root.cursor = Math.max(0, root.cursor - 1);
                    else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && root.cursor >= 0)
                        root.openCard(root.rows[root.cursor]);
                }
            }

            Column {
                id: body

                x: 1
                y: 1
                width: parent.width - 2

                // header: mark · title · worst state
                Item {
                    width: parent.width
                    height: 46

                    Text {
                        id: mark

                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: P.ICON.shield
                        color: root.pal.green
                        font.family: root.mono
                        font.pixelSize: 18
                    }

                    Text {
                        anchors.left: mark.right
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: P.APP
                        color: root.fg
                        font.family: root.mono
                        font.pixelSize: root.type.heading
                        font.weight: Font.Medium
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.worst.state !== null
                        text: root.worst.state ? P.ICON[root.worst.state] : ""
                        color: P.tint(root.pal, P.COLOR[root.worst.state])
                        font.family: root.mono
                        font.pixelSize: 18
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: root.line
                }

                Repeater {
                    model: root.rows

                    delegate: Rectangle {
                        id: rowItem

                        required property var modelData
                        required property int index

                        width: body.width
                        height: Math.max(52, info.implicitHeight + 20)
                        color: hover.containsMouse || root.cursor === index ? Qt.alpha(root.fg, 0.06) : "transparent"

                        Text {
                            id: glyph

                            x: 14
                            width: 28
                            anchors.verticalCenter: parent.verticalCenter
                            text: rowItem.modelData.icon
                            color: P.tint(root.pal, rowItem.modelData.color)
                            font.family: root.mono
                            font.pixelSize: 18
                        }

                        Column {
                            id: info

                            anchors.left: glyph.right
                            anchors.leftMargin: 10
                            anchors.right: right.left
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                                width: parent.width
                                text: rowItem.modelData.name
                                color: root.fg
                                elide: Text.ElideRight
                                font.family: root.mono
                                font.pixelSize: root.type.subtitle
                                font.weight: Font.Medium
                            }

                            Text {
                                width: parent.width
                                wrapMode: Text.WrapAnywhere
                                maximumLineCount: 2
                                textFormat: Text.StyledText
                                text: rowItem.modelData.sub + (rowItem.modelData.hasMatch ? "  " + P.ICON.commit + " " + rowItem.modelData.commitEq + " " + P.ICON.tree + " " + rowItem.modelData.treeEq : "")
                                color: root.dim
                                font.family: root.mono
                                font.pixelSize: root.type.caption
                            }
                        }

                        Row {
                            id: right

                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            Rectangle {
                                readonly property color tone: P.tint(root.pal, rowItem.modelData.chipColor)

                                anchors.verticalCenter: parent.verticalCenter
                                width: chip.implicitWidth + 12
                                height: 20
                                color: "transparent"
                                border.color: tone
                                border.width: 1

                                Text {
                                    id: chip

                                    anchors.centerIn: parent
                                    text: rowItem.modelData.chip
                                    color: parent.tone
                                    font.family: root.mono
                                    font.pixelSize: root.type.caption
                                }
                            }

                            Rectangle {
                                visible: rowItem.modelData.removable
                                width: 26
                                height: 26
                                color: removeHover.containsMouse ? Qt.alpha(root.pal.red, 0.18) : "transparent"
                                border.color: root.pal.red
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: P.ICON.remove
                                    color: root.pal.red
                                    font.family: root.mono
                                    font.pixelSize: 14
                                }

                                MouseArea {
                                    id: removeHover

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.run(P.removeArgv(rowItem.modelData.id));
                                        root.dismiss();
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: hover

                            anchors.fill: parent
                            anchors.rightMargin: right.width + 14
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openCard(rowItem.modelData)
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: 1
                            color: root.line
                        }
                    }
                }

                Text {
                    visible: root.rows.length === 0
                    width: parent.width
                    topPadding: 18
                    bottomPadding: 18
                    horizontalAlignment: Text.AlignHCenter
                    text: root.scanning ? "scanning…" : root.status ? "no third-party plugins installed" : root.statusError
                    color: root.dim
                    font.family: root.mono
                    font.pixelSize: root.type.body
                }

                // footer: rescan · site · snapshot badge
                Item {
                    width: parent.width
                    height: 50

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        FooterButton {
                            primary: true
                            visible: root.storeArgv !== null
                            icon: P.ICON.store
                            label: "store"
                            onActivated: root.openStore()
                        }

                        FooterButton {
                            icon: P.ICON.rescan
                            label: root.scanning ? "scanning…" : "rescan"
                            onActivated: root.rescan()
                        }

                        FooterButton {
                            icon: P.ICON.ext
                            label: "site"
                            onActivated: {
                                root.run(P.openArgv(P.SITE));
                                root.dismiss();
                            }
                        }
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: P.ICON.snap + " " + root.badge.text
                        color: root.badge.ok ? root.pal.green : root.pal.red
                        font.family: root.mono
                        font.pixelSize: root.type.caption

                        HoverHandler {
                            id: badgeHover
                        }
                    }

                    Text {
                        visible: badgeHover.hovered
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.bottom: parent.top
                        text: root.badge.tip
                        color: root.dim
                        font.family: root.mono
                        font.pixelSize: root.type.caption
                    }
                }
            }
        }
    }

    component FooterButton: Rectangle {
        id: btn

        property string icon: ""
        property string label: ""
        property bool primary: false

        signal activated

        width: btnText.implicitWidth + 24
        height: 30
        color: primary ? (btnHover.containsMouse ? Qt.alpha(root.pal.green, 0.85) : root.pal.green) : btnHover.containsMouse ? Qt.alpha(root.fg, 0.08) : "transparent"
        border.color: primary ? root.pal.green : Qt.alpha(root.fg, 0.25)
        border.width: 1

        Text {
            id: btnText

            anchors.centerIn: parent
            text: btn.icon + "  " + btn.label
            color: btn.primary ? root.pal.bg : root.fg
            font.weight: btn.primary ? Font.DemiBold : Font.Normal
            font.family: root.mono
            font.pixelSize: root.type.body
        }

        MouseArea {
            id: btnHover

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.activated()
        }
    }
}
