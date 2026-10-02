pragma ComponentBehavior: Bound

import QtQuick

// Installed tab (mockup renderInstalled): summary, one row per installed plugin with the
// installed vs reviewed commit, state chip, verdict and actions.
Item {
    id: view

    property int cur: -1
    readonly property var rows: Store.installedRows
    readonly property var counts: {
        const n = {
            update: 0,
            stale: 0,
            blocked: 0
        };
        for (const r of rows) {
            const s = Installer.stateOf(r);
            if (n[s] !== undefined)
                n[s]++;
        }
        return n;
    }

    function move(dir) {
        if (dir === "down")
            cur = Math.min(rows.length - 1, cur + 1);
        else if (dir === "up")
            cur = Math.max(0, cur - 1);
        list.positionViewAtIndex(Math.max(0, cur), ListView.Contain);
    }

    function current() {
        return cur >= 0 ? rows[cur] || null : null;
    }

    function activate() {
        const r = current();
        if (r)
            Store.open(r);
    }

    Row {
        id: sum

        x: 20
        y: 10
        spacing: 14
        height: 24

        Txt {
            text: view.rows.length + " installed"
            size: 11
            weight: Font.Medium
            anchors.verticalCenter: parent.verticalCenter
        }

        Txt {
            text: view.counts.update + " update"
            size: 11
            color: Theme.blue
            anchors.verticalCenter: parent.verticalCenter
        }

        Txt {
            text: view.counts.stale + " stale"
            size: 11
            color: Theme.blue
            anchors.verticalCenter: parent.verticalCenter
        }

        Txt {
            text: view.counts.blocked + " blocked"
            size: 11
            color: Theme.red
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: 20
        y: 10
        spacing: 6

        Btn {
            sm: true
            icon: "up"
            label: "update all (" + view.counts.update + ")"
            enabledState: Installer.canInstall && view.counts.update > 0
            tipText: Installer.why
            tipRight: true
            onClicked: {
                for (const r of view.rows)
                    if (Installer.stateOf(r) === "update") {
                        Store.askInstall(r, true);
                        break;
                    }
            }
        }

        Btn {
            sm: true
            kind: "ghost"
            icon: "search"
            label: "rescan"
            onClicked: Store.refreshInstalled()
        }
    }

    Item {
        id: head

        anchors.top: sum.bottom
        anchors.topMargin: 10
        x: 20
        width: parent.width - 40
        height: 30

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Theme.borderStrong
        }

        Repeater {
            model: [[44, "PLUGIN"], [head.width * 0.36, "INSTALLED · REVIEWED"], [head.width * 0.36 + 160, "STATE"], [head.width * 0.36 + 300, "VERDICT"]]

            Txt {
                required property var modelData

                x: modelData[0]
                anchors.verticalCenter: parent.verticalCenter
                text: modelData[1]
                size: 10
                color: Theme.muted
                font.letterSpacing: 1.2
            }
        }

        Txt {
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: "ACTIONS"
            size: 10
            color: Theme.muted
            font.letterSpacing: 1.2
        }
    }

    ListView {
        id: list

        anchors.top: head.bottom
        anchors.bottom: foot.top
        x: 20
        width: parent.width - 40
        clip: true
        model: view.rows

        delegate: InstalledRow {
            required property var modelData
            required property int index

            width: list.width
            rec: modelData
            current: index === view.cur
        }
    }

    Txt {
        id: foot

        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        x: 20
        width: parent.width - 40
        size: 10
        color: Theme.muted
        text: "stale = installed HEAD ≠ reviewed commit (no verdict for the running code) · update = a newer reviewed commit exists · blocked = provider found hard-fail evidence after install" + (Installer.dev ? " · --dev: fixed sample list" : "")
    }

    Txt {
        visible: view.rows.length === 0
        anchors.centerIn: parent
        text: Store.loaded ? "no plugins installed in ~/.config/omarchy/plugins" : "loading…"
        color: Theme.muted
    }
}
