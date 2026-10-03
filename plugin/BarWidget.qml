pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "lib/panel.mjs" as P

// Bar shield (mockup "bar · BarWidget.qml"): tinted by the worst state of the installed
// plugins, with how many share it (no number when all are safe). Reads the cached
// status.json through a watched FileView: no timer, no polling. Left click opens the
// omarchy-store window (single instance: a second click focuses it, ADR-0042), right click
// toggles the verdict panel, middle click rescans once (`omarchy-plugin-check status --json`).
BarWidget {
    id: root

    property var status: null
    property var pal: P.palette("")

    readonly property string home: Quickshell.env("HOME")
    readonly property string bin: P.cliPath(Qt.resolvedUrl("."))
    readonly property var storeArgv: P.storeArgv(Qt.resolvedUrl("."))
    readonly property var worst: P.worst(status)
    // why: the host injects `bar` as a plain QtObject; qmllint cannot see its members.
    readonly property var host: bar
    readonly property color barFg: host ? host.barForeground : Color.foreground

    moduleName: P.PLUGIN_ID
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    function rescan() {
        const argv = P.rescanArgv(bin);
        if (argv && !scanProc.running) {
            scanProc.command = argv;
            scanProc.running = true;
        }
    }

    FileView {
        id: statusFile

        path: root.home + "/.cache/omarchy-plugin-check/status.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.status = P.parseStatus(text()).doc
        onLoadFailed: root.status = null
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
        onExited: statusFile.reload()
    }

    WidgetButton {
        id: button

        anchors.fill: parent
        bar: root.bar
        text: P.shieldLabel(root.worst)
        foreground: root.worst.state === null ? Qt.alpha(root.barFg, 0.6) : P.tint(root.pal, P.COLOR[root.worst.state])
        tooltipText: P.shieldTip(root.worst, root.status)
        onPressed: function (b) {
            if (b === Qt.MiddleButton)
                root.rescan();
            else if (b === Qt.LeftButton && root.storeArgv)
                Quickshell.execDetached(root.storeArgv);
            else if (root.host)
                root.host.run("omarchy-shell shell toggle " + P.PLUGIN_ID + " '{}'");
        }
    }
}
