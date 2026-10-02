pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/theme.mjs" as T

// Design tokens from the current Omarchy theme (~/.local/state/omarchy/current/theme,
// colors.toml), mapped by lib/theme.mjs onto the mockup's names. Live: a theme switch
// rewrites colors.toml and the store recolours. Dev builds cycle installed themes with `t`.
Singleton {
    id: root

    readonly property string font: "JetBrainsMono Nerd Font"
    readonly property bool dev: Quickshell.env("OPC_STORE_DEV") === "1"
    readonly property string home: Quickshell.env("HOME")
    readonly property string currentDir: home + "/.local/state/omarchy/current/theme"

    // Dev override (`t`): a theme directory name, "" = follow the current Omarchy theme.
    property string override: ""
    property var names: []
    property string currentName: ""
    readonly property string name: override !== "" ? override : currentName
    property var t: T.tokens({}, "tokyo-night")

    readonly property color bg: t.bg
    readonly property color bgDeep: t.bgDeep
    readonly property color surface: t.surface
    readonly property color surface2: t.surface2
    readonly property color borderSubtle: t.borderSubtle
    readonly property color borderStrong: t.borderStrong
    readonly property color text: t.text
    readonly property color textSecondary: t.textSecondary
    readonly property color muted: t.muted
    readonly property color brand: t.brand
    readonly property color red: t.red
    readonly property color yellow: t.yellow
    readonly property color green: t.green
    readonly property color blue: t.blue
    readonly property color orange: t.orange
    readonly property color purple: t.purple
    readonly property color cyan: t.cyan
    readonly property color mark: t.mark

    // Outcome / accent token name ("green", "muted", ...) -> colour.
    function c(token) {
        switch (token) {
        case "green":
            return green;
        case "yellow":
            return yellow;
        case "orange":
            return orange;
        case "red":
            return red;
        case "blue":
            return blue;
        case "purple":
            return purple;
        case "cyan":
            return cyan;
        case "brand":
            return brand;
        case "muted":
            return muted;
        case "text":
            return text;
        default:
            return textSecondary;
        }
    }

    function cycle() {
        if (!dev || names.length === 0)
            return;
        override = T.nextTheme(names, name);
    }

    FileView {
        id: colors
        path: root.override !== "" ? root.overridePath : root.currentDir + "/colors.toml"
        watchChanges: root.override === ""
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.t = T.tokens(T.parseColors(text()), root.name)
    }

    property string overridePath: ""
    onOverrideChanged: {
        overridePath = override === "" ? "" : (userThemes.indexOf(override) !== -1 ? home + "/.config/omarchy/themes/" : "/usr/share/omarchy/themes/") + override + "/colors.toml";
    }
    property var userThemes: []

    FileView {
        path: root.home + "/.local/state/omarchy/current/theme.name"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.currentName = text().trim()
    }

    Process {
        running: root.dev
        command: ["sh", "-c", "ls -1 \"$HOME/.config/omarchy/themes\" 2>/dev/null | sed 's/^/u:/'; ls -1 /usr/share/omarchy/themes 2>/dev/null"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const all = [];
                const user = [];
                for (const line of text.split("\n")) {
                    const n = line.trim();
                    if (!n)
                        continue;
                    const isUser = n.indexOf("u:") === 0;
                    const id = isUser ? n.slice(2) : n;
                    if (isUser)
                        user.push(id);
                    if (all.indexOf(id) === -1)
                        all.push(id);
                }
                all.sort();
                root.userThemes = user;
                root.names = all;
            }
        }
    }
}
