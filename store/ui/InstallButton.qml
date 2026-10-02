pragma ComponentBehavior: Bound

import QtQuick

// The install/open/update/remove action group (mockup installBtn()).
Row {
    id: ib

    property var rec: ({})
    property bool sm: false
    readonly property string inst: Installer.installedVersion >= 0 ? Installer.stateOf(rec) : ""

    spacing: 6

    Btn {
        visible: ib.rec.verdict === "blocked"
        kind: "danger"
        sm: ib.sm
        icon: "blocked"
        label: "blocked"
        enabledState: false
        tipText: "blocked: install refused"
    }

    Btn {
        visible: ib.rec.verdict !== "blocked" && ib.inst !== ""
        kind: "primary"
        sm: ib.sm
        icon: "play"
        label: "open"
        onClicked: Store.showToast("omarchy plugin toggle · opened " + ib.rec.name)
    }

    Btn {
        visible: ib.rec.verdict !== "blocked" && (ib.inst === "update" || ib.inst === "stale")
        sm: ib.sm
        icon: "up"
        label: ib.inst === "stale" ? "re-pin" : "update"
        enabledState: Installer.canInstall
        tipText: Installer.why
        onClicked: Store.askInstall(ib.rec, true)
    }

    Btn {
        visible: ib.rec.verdict !== "blocked" && ib.inst !== ""
        kind: "ghost"
        sm: ib.sm
        icon: "trash"
        label: "remove"
        onClicked: Store.askRemove(ib.rec)
    }

    Btn {
        visible: ib.rec.verdict !== "blocked" && ib.inst === ""
        kind: !Installer.canInstall ? "" : ib.rec.verdict === "safe" ? "primary" : ib.rec.verdict === "caution" ? "caution" : ib.rec.verdict === "risky" ? "risky" : ""
        sm: ib.sm
        icon: "dl"
        label: "install"
        key: "i"
        enabledState: Installer.canInstall
        tipText: Installer.why
        onClicked: Store.askInstall(ib.rec)
    }
}
