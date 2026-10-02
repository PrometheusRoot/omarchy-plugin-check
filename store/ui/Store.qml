pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import QtQml.WorkerScript
import Quickshell
import Quickshell.Io
import "../lib/data.mjs" as Data

// App state + the data worker. The snapshot is read here (FileView) and handed to
// ui/worker.mjs, which parses, maps (lib/data.mjs), indexes and searches (ADR-0026).
// The UI only holds the records it displays. The home payload is cached on disk so the
// next cold start paints the home tab before the worker has parsed anything.
Singleton {
    id: store

    readonly property bool dev: Quickshell.env("OPC_STORE_DEV") === "1"
    readonly property string home: Quickshell.env("HOME")
    readonly property string cacheDir: home + "/.cache/omarchy-plugin-check"
    readonly property string devSnapshot: Quickshell.shellDir + "/dev/store.json"
    readonly property string realSnapshot: Quickshell.env("OPC_STORE_SNAPSHOT") || cacheDir + "/store.json"
    property string snapshotPath: dev ? devSnapshot : realSnapshot
    // The 5 MB snapshot goes to the worker right away on a cold cache, but only after the
    // first frame when the home tab came from the disk cache (2 cores: don't compete).
    property bool wantSnapshot: false
    property bool usingDev: dev
    property bool snapshotMissing: false
    // Launch time from the launcher (true cold start), else QML load.
    readonly property bool launched: Number(Quickshell.env("OPC_STORE_T0")) > 0
    readonly property real startedAt: Number(Quickshell.env("OPC_STORE_T0")) || Date.now()
    Component.onCompleted: timings = Object.assign({}, timings, {
        storeAt: Date.now() - startedAt
    })

    // --- data -------------------------------------------------------------------------
    property var data: null // home payload (lib/service.mjs homePayload)
    property bool homeFromCache: false
    property bool loaded: false // worker has the snapshot
    property bool indexed: false
    property var timings: ({})
    property int total: data ? data.total : 0
    property var meta: data ? data.meta : ({})

    // --- navigation -------------------------------------------------------------------
    property string tab: "home" // home search browse installed status detail
    property string prevTab: "home"
    property int hero: 0
    property bool searchFocused: false

    // --- search -----------------------------------------------------------------------
    property string query: ""
    property var filters: ({
            cat: "all",
            kind: "all",
            verdict: "all",
            inst: false
        })
    property string sort: "rank"
    property var results: []
    property int resultCount: 0
    property real resultMs: 0
    property var words: []
    property int seq: 0
    property int shownSeq: 0
    property bool paging: false

    // --- browse / installed / detail --------------------------------------------------
    property string browseCat: "all"
    property var browseRows: []
    property var installedRows: []
    property var rec: null // plugin shown in detail
    property string section: "overview"
    property var detail: null // lib/data.mjs fromDetail
    property bool detailLoading: false
    property var similar: []
    property int gallery: 0

    // --- overlays ---------------------------------------------------------------------
    property string dialog: "" // install rank remove
    property var dialogRec: null
    property string toast: ""
    property var bench: null

    signal resultsReset

    onDataChanged: {
        if (data && timings.homeAt === undefined) {
            timings = Object.assign({}, timings, {
                homeAt: Date.now() - startedAt
            });
            console.info("store: home ready", timings.homeAt, "ms", homeFromCache ? "(disk cache)" : "(worker)");
        }
    }

    function go(t) {
        if (t !== "detail")
            prevTab = t;
        tab = t;
        if (t === "installed")
            refreshInstalled();
        if (t === "browse" && browseCat !== "all")
            requestBrowse();
        if (t === "search" && shownSeq === 0)
            runSearch();
    }

    function back() {
        if (dialog !== "") {
            closeDialog();
            return true;
        }
        if (tab === "detail") {
            tab = prevTab;
            return true;
        }
        if (tab === "search" && query !== "") {
            query = "";
            runSearch();
            return true;
        }
        return false;
    }

    // --- worker protocol ----------------------------------------------------------------
    function send(msg) {
        worker.sendMessage(msg);
    }

    function runSearch() {
        if (!loaded)
            return;
        seq++;
        const f = Object.assign({}, filters);
        f.instVersion = Installer.installedVersion;
        send({
            type: "search",
            seq: seq,
            q: query,
            f: f,
            sort: sort,
            installed: Installer.installed,
            limit: 60
        });
    }

    function setQuery(q) {
        query = q;
        if (tab !== "search" && tab !== "detail")
            go("search");
        runSearch();
    }

    function setFilter(key, value) {
        const f = Object.assign({}, filters);
        f[key] = value;
        filters = f;
        if (tab !== "search" && tab !== "browse")
            go("search");
        if (tab === "browse")
            requestBrowse();
        else
            runSearch();
    }

    function setSort(s) {
        sort = s;
        runSearch();
    }

    function more() {
        if (paging || results.length >= resultCount)
            return;
        paging = true;
        send({
            type: "page",
            seq: shownSeq,
            offset: results.length,
            limit: 60
        });
    }

    function requestBrowse() {
        if (!loaded || browseCat === "all")
            return;
        send({
            type: "browse",
            cat: browseCat,
            kind: filters.kind,
            limit: 30
        });
    }

    function openCat(c) {
        browseCat = c;
        go("browse");
        requestBrowse();
    }

    // "see all ›" on a shelf -> search sorted like the shelf.
    function seeAll(shelf) {
        const sorts = {
            top: "rank",
            trending: "trending",
            "new": "new",
            updated: "updated",
            safePicks: "rank"
        };
        sort = sorts[shelf] || "rank";
        if (shelf === "safePicks") {
            const f = Object.assign({}, filters);
            f.verdict = "safe";
            filters = f;
        }
        go("search");
        runSearch();
    }

    function refreshInstalled() {
        if (!loaded)
            return;
        send({
            type: "records",
            tag: "installed",
            ids: Object.keys(Installer.installed)
        });
    }

    function open(r) {
        if (!r)
            return;
        rec = r;
        section = "overview";
        gallery = 0;
        detail = null;
        similar = [];
        go("detail");
        loadDetail(r);
        if (loaded)
            send({
                type: "similar",
                id: r.id
            });
    }

    function openId(id) {
        send({
            type: "records",
            tag: "open",
            ids: [id]
        });
    }

    function loadDetail(r) {
        if (!r.report) {
            detailLoading = false;
            return;
        }
        detailLoading = true;
        const base = meta.apiBase || "";
        if (/^https:\/\//.test(base)) {
            detailFetch.target = cacheDir + "/api/" + r.id + ".json";
            detailFetch.command = ["sh", "-c", "mkdir -p \"$(dirname \"$2\")\" && curl -fsSL --proto =https --max-time 20 -o \"$2.part\" -- \"$1\" && mv -f \"$2.part\" \"$2\"", "fetch", base.replace(/\/+$/, "") + "/" + r.report, detailFetch.target];
            detailFetch.running = true;
        } else {
            const dir = snapshotPath.replace(/\/[^/]*$/, "");
            detailFile.path = (dir + "/" + base + "/" + r.report).replace(/\/{2,}/g, "/");
        }
    }

    function showToast(t) {
        toast = t;
        toastTimer.restart();
    }

    function askInstall(r, repin) {
        if (!r)
            return;
        if (!repin && Installer.installed[r.id] && Installer.state !== "running") {
            showToast(r.name + " is already installed");
            return;
        }
        if (Installer.state === "running" && Installer.rec && Installer.rec.id === r.id) {
            dialog = "install";
            return;
        }
        Installer.begin(r, !!repin);
        if (Installer.state === "idle")
            return;
        dialogRec = r;
        dialog = "install";
    }

    function askRemove(r) {
        dialogRec = r;
        dialog = "remove";
    }

    function closeDialog() {
        if (dialog === "install")
            Installer.close();
        dialog = "";
    }

    function rankDialog(r) {
        dialogRec = r;
        dialog = "rank";
    }

    function runBench() {
        bench = null;
        send({
            type: "bench",
            phrases: ["weather", "omarchy clock", "github", "spotify player", "ytdlp", "theme switcher"],
            reps: 3
        });
    }

    function onReply(m) {
        switch (m.type) {
        case "loaded":
            homeFromCache = false;
            data = m.home;
            loaded = true;
            timings = Object.assign({}, timings, {
                parse: m.ms.parse,
                map: m.ms.map,
                loadedAt: Date.now() - startedAt
            });
            console.info("store: snapshot in worker: parse", m.ms.parse, "ms, map", m.ms.map, "ms,", m.home.total, "plugins; loaded at", timings.loadedAt, "ms");
            homeCache.setText(JSON.stringify({
                path: snapshotPath,
                version: m.home.meta.version,
                home: m.home
            }));
            send({
                type: "index"
            });
            refreshInstalled();
            if (tab === "search" || query !== "")
                runSearch();
            if (tab === "browse")
                requestBrowse();
            if (rec)
                send({
                    type: "similar",
                    id: rec.id
                });
            break;
        case "indexed":
            indexed = true;
            timings = Object.assign({}, timings, {
                index: m.ms.index,
                warm: m.ms.warm,
                indexedAt: Date.now() - startedAt
            });
            console.info("store: index", m.ms.index, "ms, warm", m.ms.warm, "ms; searchable at", timings.indexedAt, "ms");
            break;
        case "results":
            if (m.seq !== seq)
                return; // a newer keystroke is in flight
            shownSeq = m.seq;
            results = m.rows;
            resultCount = m.count;
            resultMs = m.ms;
            words = m.words;
            resultsReset();
            break;
        case "page":
            paging = false;
            if (m.seq === shownSeq && m.offset === results.length)
                results = results.concat(m.rows);
            break;
        case "browse":
            if (m.cat === browseCat)
                browseRows = m.rows;
            break;
        case "records":
            if (m.tag === "installed")
                installedRows = m.rows;
            else if (m.tag === "open" && m.rows.length)
                open(m.rows[0]);
            break;
        case "similar":
            if (rec && m.id === rec.id)
                similar = m.rows;
            break;
        case "bench":
            bench = m;
            break;
        case "error":
            console.warn("store worker:", m.on, m.error);
            break;
        }
    }

    WorkerScript {
        id: worker

        source: Qt.resolvedUrl("worker.mjs")
        onMessage: m => store.onReply(m)
    }

    function frameShown() {
        if (!wantSnapshot)
            Qt.callLater(() => store.wantSnapshot = true);
    }

    FileView {
        id: snapshot

        path: store.wantSnapshot ? store.snapshotPath : ""
        printErrors: false
        onLoaded: {
            store.timings = Object.assign({}, store.timings, {
                readAt: Date.now() - store.startedAt
            });
            store.send({
                type: "load",
                text: text()
            });
        }
        onLoadFailed: {
            if (!store.usingDev) {
                // No published snapshot on this machine yet: fall back to the bundled
                // dev snapshot, flagged "dev" in the header.
                store.usingDev = true;
                store.snapshotPath = store.devSnapshot;
            } else if (!unpack.tried) {
                unpack.tried = true;
                unpack.running = true;
            } else {
                store.snapshotMissing = true;
            }
        }
    }

    // store/dev/store.json is committed gzipped; unpack it on first run.
    Process {
        id: unpack

        property bool tried: false

        command: ["gunzip", "-kf", store.devSnapshot + ".gz"]
        onExited: code => {
            if (code === 0)
                snapshot.reload();
            else
                store.snapshotMissing = true;
        }
    }

    FileView {
        id: homeCache

        path: store.cacheDir + "/store-home.json"
        printErrors: false
        atomicWrites: true
        onLoaded: {
            if (store.data)
                return;
            try {
                const c = JSON.parse(text());
                if (c.path === store.snapshotPath && c.home) {
                    store.homeFromCache = true;
                    store.data = c.home;
                    store.timings = Object.assign({}, store.timings, {
                        homeCacheAt: Date.now() - store.startedAt
                    });
                    return;
                }
            } catch (e) {
                console.warn("store: ignoring home cache:", e);
            }
            store.wantSnapshot = true;
        }
        onLoadFailed: store.wantSnapshot = true
    }

    FileView {
        id: detailFile

        printErrors: false
        onLoaded: {
            try {
                store.detail = Data.fromDetail(JSON.parse(text()), store.meta.providers || []);
            } catch (e) {
                console.warn("store: bad detail file:", e);
                store.detail = null;
            }
            store.detailLoading = false;
        }
        onLoadFailed: store.detailLoading = false
    }

    Process {
        id: detailFetch

        property string target: ""

        onExited: code => {
            if (code === 0) {
                detailFile.path = "";
                detailFile.path = target;
            } else {
                store.detailLoading = false;
            }
        }
    }

    Timer {
        id: toastTimer

        interval: 2600
        onTriggered: store.toast = ""
    }

    Connections {
        target: Installer

        function onFinished(r, ok) {
            store.showToast(ok ? "installed " + r.name + (r.commit ? " · pinned " + String(r.commit).slice(0, 7) : "") : "install failed · " + r.name);
            store.refreshInstalled();
        }

        function onRemoved(id) {
            store.showToast("removed " + id + " · omarchy plugin remove");
            store.refreshInstalled();
        }

        function onInstalledVersionChanged() {
            store.refreshInstalled();
        }
    }
}
