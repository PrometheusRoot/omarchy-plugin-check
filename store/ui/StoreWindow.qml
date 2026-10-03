pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/nav.mjs" as Nav

// The store's own floating window (ADR-0014): 1280x800, Omarchy draws no decorations so
// the app draws its header. Every key goes through lib/nav.mjs keyAction (mockup key map).
FloatingWindow {
    id: win

    title: "omarchy-store"
    implicitWidth: 1280
    implicitHeight: 800
    minimumSize: Qt.size(960, 600)
    color: Theme.bg

    // why: Quickshell has no quit() for configs; closing the window ends the app, so the
    // config signals its own process (sh's parent is quickshell).
    onVisibleChanged: if (!visible)
        quitProc.running = true

    Process {
        id: quitProc

        command: ["sh", "-c", "kill -TERM \"$PPID\""]
    }

    property var seen: ({
            home: true
        })

    Connections {
        target: Store

        function onTabChanged() {
            if (win.seen[Store.tab] !== true) {
                const s = Object.assign({}, win.seen);
                s[Store.tab] = true;
                win.seen = s;
            }
        }

        function onDialogChanged() {
            if (Store.dialog !== "" && win.seen.overlay !== true)
                win.seen = Object.assign({}, win.seen, {
                    overlay: true
                });
        }
    }

    function view() {
        switch (Store.tab) {
        case "home":
            return homeView;
        case "search":
            return searchView.item;
        case "browse":
            return browseView.item;
        case "installed":
            return installedView.item;
        case "status":
            return statusView.item;
        default:
            return detailView.item;
        }
    }

    function dialogCtx() {
        if (Store.dialog === "install")
            return Installer.state === "confirm" ? "confirm" : Installer.state || "install";
        if (Store.dialog === "extras")
            return Extras.state === "confirm" ? "confirm" : "extras";
        return Store.dialog;
    }

    // The search field sits inside the key scope: drop its focus flag, or forcing focus on
    // the scope hands it straight back to the field.
    function blurInput() {
        header.input.focus = false;
        keys.forceActiveFocus();
    }

    function leaveInput() {
        blurInput();
        if (Store.tab !== "search")
            Store.go("search");
        if (searchView.item)
            searchView.item.cur = 0;
    }

    function dispatch(a) {
        const v = view();
        if (!v && a.action !== "back" && a.action !== "tab" && a.action !== "focusSearch")
            return false;
        switch (a.action) {
        case "back":
            Store.back();
            blurInput();
            return true;
        case "confirm":
            if (overlays.item)
                (overlays.item as Overlays).confirmAction();
            return true;
        case "dialogDefault":
            if (overlays.item)
                (overlays.item as Overlays).defaultAction();
            return true;
        case "leaveInput":
            leaveInput();
            return true;
        case "focusSearch":
            if (Store.tab !== "search" && Store.tab !== "detail")
                Store.go("search");
            header.input.forceActiveFocus();
            header.input.selectAll();
            return true;
        case "tab":
            Store.go(a.arg);
            return true;
        case "move":
            v.move(a.arg);
            return true;
        case "page":
            if (v.page)
                v.page(a.arg);
            return true;
        case "hero":
            homeView.stepHero(a.arg);
            return true;
        case "open":
            v.activate();
            return true;
        case "install":
            {
                const p = v.current();
                if (p)
                    Store.askInstall(p);
                return true;
            }
        case "rank":
            Store.rankDialog(Store.tab === "detail" ? Store.rec : v.current());
            return true;
        case "theme":
            Theme.cycle();
            return true;
        case "section":
            Store.section = a.arg;
            return true;
        case "extras":
            Extras.open(false);
            return true;
        default:
            return false;
        }
    }

    function onKey(event, inInput) {
        const mods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier);
        const key = Nav.keyName(event.key, event.text);
        const a = Nav.keyAction(key, {
            inInput: inInput,
            dialog: dialogCtx(),
            tab: Store.tab,
            cursor: Store.tab === "home" ? homeView.cur !== null : true,
            dev: Theme.dev,
            mods: mods !== 0
        });
        event.accepted = dispatch(a);
    }

    FocusScope {
        id: keys

        anchors.fill: parent
        focus: true
        Keys.onPressed: event => win.onKey(event, false)

        Header {
            id: header

            width: parent.width
            z: 3
            input.Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape || event.key === Qt.Key_Down || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                    win.onKey(event, true);
            }
        }

        Item {
            id: body

            anchors.top: header.bottom
            anchors.bottom: footer.top
            width: parent.width
            clip: true

            HomeView {
                id: homeView

                anchors.fill: parent
                visible: Store.tab === "home"
            }

            // Only home is built at start; other tabs load on first visit (cold start).
            Loader {
                id: searchView

                anchors.fill: parent
                active: win.seen.search === true
                visible: Store.tab === "search"
                sourceComponent: SearchView {}
            }

            Loader {
                id: browseView

                anchors.fill: parent
                active: win.seen.browse === true
                visible: Store.tab === "browse"
                sourceComponent: BrowseView {}
            }

            Loader {
                id: installedView

                anchors.fill: parent
                active: win.seen.installed === true
                visible: Store.tab === "installed"
                sourceComponent: InstalledView {}
            }

            Loader {
                id: statusView

                anchors.fill: parent
                active: win.seen.status === true
                visible: Store.tab === "status"
                sourceComponent: StatusView {}
            }

            Loader {
                id: detailView

                anchors.fill: parent
                active: win.seen.detail === true
                visible: Store.tab === "detail"
                sourceComponent: DetailView {}
            }

            Loader {
                id: overlays

                anchors.fill: parent
                z: 10
                active: win.seen.overlay === true || Store.dialog !== "" || Store.toast !== ""
                sourceComponent: Overlays {}
            }
        }

        Footer {
            id: footer

            anchors.bottom: parent.bottom
            width: parent.width
        }
    }

    Component.onCompleted: {
        Store.timings = Object.assign({}, Store.timings, {
            windowAt: Date.now() - Store.startedAt
        });
    }

    // First rendered frame (FrameAnimation ticks in step with the scene graph).
    FrameAnimation {
        running: Store.timings.firstFrame === undefined
        onTriggered: {
            Store.timings = Object.assign({}, Store.timings, {
                firstFrame: Date.now() - Store.startedAt
            });
            console.info("store: first frame", Store.timings.firstFrame, "ms", JSON.stringify(Store.timings));
            Store.frameShown();
        }
    }
}
