pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import QtQml.WorkerScript
import Quickshell
import Quickshell.Io
import "../lib/data.mjs" as Data

// App state + the data worker over the client bundle (ADR-0032). Start: verify the bundle
// (bin/omarchy-plugin-store-verify: manifest signature, expiry, rollback, sha256 of every
// file) -> map the small home slice here for the first frame (lib/data.mjs fromHome) ->
// after the first frame hand the search columns to ui/worker.mjs, which maps, indexes and
// searches (ADR-0031). Detail documents are verified and loaded lazily per plugin.
Singleton {
    id: store

    readonly property bool dev: Quickshell.env("OPC_STORE_DEV") === "1"
    readonly property string home: Quickshell.env("HOME")
    readonly property string cacheDir: home + "/.cache/omarchy-plugin-check"
    readonly property string devBundle: Quickshell.shellDir + "/dev"
    readonly property string realBundle: Quickshell.env("OPC_STORE_BUNDLE") || cacheDir
    readonly property string verifier: Quickshell.shellDir + "/bin/omarchy-plugin-store-verify"
    // Bundle directory in use (store-manifest.json, store-home.json, store-search.json, ...).
    property string snapshotPath: dev ? devBundle : realBundle
    // The search columns go to the worker after the first frame (2 cores: don't compete).
    property bool wantSnapshot: false
    property bool usingDev: dev
    property bool snapshotMissing: false
    property string verifyError: "" // non-empty: the bundle failed verification and is not used
    property var homeShelves: ({}) // raw shelf ids from the home slice (worker: "similar")
    // Launch time from the launcher (true cold start), else QML load.
    readonly property bool launched: Number(Quickshell.env("OPC_STORE_T0")) > 0
    readonly property real startedAt: Number(Quickshell.env("OPC_STORE_T0")) || Date.now()
    Component.onCompleted: timings = Object.assign({}, timings, {
        storeAt: Date.now() - startedAt
    })

    // --- data -------------------------------------------------------------------------
    property var data: null // home payload (lib/data.mjs fromHome)
    property bool loaded: false // worker has the search columns
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
            console.info("store: home ready", timings.homeAt, "ms (verified bundle", timings.verify, "ms, home slice", timings.homeMap, "ms)");
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

    // Detail documents: verified against store-details.json by the verifier, which prints
    // the document (fetching it first when apiBase is https). One request at a time; the
    // newest wins. `purpose` "detail" fills the detail view, "rank" completes dialogRec.
    function loadDetail(r) {
        if (!r || !r.report) {
            detailLoading = false;
            return;
        }
        detailLoading = true;
        requestDetail(r.id);
    }

    function requestDetail(id) {
        detailProc.wanted = id;
        if (detailProc.running)
            return;
        detailProc.pluginId = id;
        detailProc.command = [verifier, "detail", snapshotPath, id];
        detailProc.running = true;
    }

    function detailArrived(id, text) {
        let d = null;
        try {
            d = Data.fromDetail(JSON.parse(text), meta.providers || [], meta.imageBase || "");
        } catch (e) {
            console.warn("store: bad detail document:", id, e);
        }
        if (rec && rec.id === id) {
            detail = d;
            detailLoading = false;
            if (d && d.listing)
                rec = Object.assign({}, rec, d.listing);
        }
        if (dialogRec && dialogRec.id === id && d && d.listing)
            dialogRec = Object.assign({}, dialogRec, d.listing);
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
        // Search rows carry no factor details; the detail document's listing does.
        if (r && !r.complete && r.report)
            requestDetail(r.id);
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
            loaded = true;
            timings = Object.assign({}, timings, {
                parse: m.ms.parse,
                map: m.ms.map,
                loadedAt: Date.now() - startedAt
            });
            console.info("store: search columns in worker: parse", m.ms.parse, "ms, map", m.ms.map, "ms,", m.total, "plugins; loaded at", timings.loadedAt, "ms");
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
                indexedAt: Date.now() - startedAt
            });
            console.info("store: index", m.ms.index, "ms; searchable at", timings.indexedAt, "ms");
            send({
                type: "warm",
                from: 0,
                count: 4
            });
            break;
        case "warmed":
            timings = Object.assign({}, timings, {
                warm: (timings.warm || 0) + m.ms
            });
            if (m.next >= 0)
                send({
                    type: "warm",
                    from: m.next,
                    count: 4
                });
            else {
                console.info("store: warm", timings.warm, "ms; warm at", Date.now() - startedAt, "ms");
                if (Quickshell.env("OPC_STORE_BENCH") === "1")
                    runBench(); // tools/coldstart.sh --bench
            }
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
            console.info("store: bench", m.n, "keystrokes p50", m.p50, "p95", m.p95, "p99", m.p99, "ms");
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

    // 1. verify the manifest + the home slice (real bundle only; the dev data ships with the
    // app). Exit 3 = no bundle here. The search columns are verified in step 3.
    Process {
        id: verify

        running: !store.usingDev
        command: [store.verifier, "bundle", store.realBundle, "home"]
        stderr: StdioCollector {
            id: verifyErr
        }
        onExited: code => {
            store.timings = Object.assign({}, store.timings, {
                verify: Date.now() - store.startedAt
            });
            if (code === 0) {
                homeFile.path = store.snapshotPath + "/store-home.json";
            } else if (code === 3) {
                // No published bundle on this machine yet: the bundled dev data, flagged "dev".
                store.usingDev = true;
                store.snapshotPath = store.devBundle;
                homeFile.path = store.devBundle + "/store-home.json";
            } else {
                store.verifyError = verifyErr.text.trim() || "verification failed";
                console.warn("store: refusing the snapshot:", store.verifyError);
            }
        }
    }

    // 2. home slice, mapped here (small) so the first frame shows content.
    FileView {
        id: homeFile

        path: store.dev ? store.devBundle + "/store-home.json" : ""
        printErrors: false
        onLoaded: {
            const t0 = Date.now();
            try {
                const raw = JSON.parse(text());
                store.homeShelves = raw.shelves ? raw.shelves.byCategory || {} : {};
                const d = Data.fromHome(raw);
                store.timings = Object.assign({}, store.timings, {
                    homeMap: Date.now() - t0
                });
                store.data = d;
            } catch (e) {
                store.verifyError = "bad home slice: " + e;
            }
        }
        onLoadFailed: {
            if (store.usingDev && !unpack.tried) {
                unpack.tried = true;
                unpack.running = true;
            } else {
                store.snapshotMissing = true;
            }
        }
    }

    // store/dev/*.json are committed gzipped; unpack them on first run.
    Process {
        id: unpack

        property bool tried: false

        command: ["gunzip", "-kf", store.devBundle + "/store-home.json.gz", store.devBundle + "/store-search.json.gz"]
        onExited: code => {
            if (code === 0)
                homeFile.reload();
            else
                store.snapshotMissing = true;
        }
    }

    // 3. after the first frame: verify the search columns + detail hashes, then -> worker.
    property bool searchVerified: false

    Process {
        id: verifySearch

        running: store.wantSnapshot && !!store.data && !store.usingDev && !store.searchVerified && store.verifyError === ""
        command: [store.verifier, "bundle", store.snapshotPath, "search", "details"]
        stderr: StdioCollector {
            id: verifySearchErr
        }
        onExited: code => {
            if (code === 0)
                store.searchVerified = true;
            else
                store.verifyError = verifySearchErr.text.trim() || "search file failed verification";
        }
    }

    FileView {
        id: searchFile

        path: store.wantSnapshot && store.data && (store.usingDev || store.searchVerified) ? store.snapshotPath + "/store-search.json" : ""
        printErrors: false
        onLoaded: {
            store.timings = Object.assign({}, store.timings, {
                readAt: Date.now() - store.startedAt
            });
            store.send({
                type: "load",
                text: text(),
                imageBase: store.meta.imageBase || "",
                byCategory: store.homeShelves
            });
        }
        onLoadFailed: console.warn("store: no search file in", store.snapshotPath)
    }

    // 4. detail documents, verified per plugin.
    Process {
        id: detailProc

        property string pluginId: ""
        property string wanted: ""

        stdout: StdioCollector {
            id: detailOut
        }
        onExited: code => {
            if (code === 0)
                store.detailArrived(pluginId, detailOut.text);
            else if (store.rec && store.rec.id === pluginId)
                store.detailLoading = false;
            if (wanted !== pluginId)
                store.requestDetail(wanted);
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
