pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/imgcache.mjs" as IC

// Disk image cache: ~/.cache/omarchy-plugin-check/img/<hash>.<ext>. Delegates ask
// `path(url)`: a known file returns file://..., otherwise "" and the URL is queued; up to
// MAX_PARALLEL curl downloads run at once (newest request first). `version` bumps when a
// file lands so visible thumbnails re-bind; Qt decodes asynchronously.
Singleton {
    id: root

    readonly property string dir: Quickshell.env("HOME") + "/.cache/omarchy-plugin-check/img"
    property var known: ({})
    // why: mutable bookkeeping lives in one never-reassigned object so that path(), which
    // runs inside thumbnail bindings, can queue work without notifying (no binding loop).
    readonly property var st: ({
            queue: [],
            failed: {},
            active: {}
        })
    property int running: 0
    property int queued: 0
    property int version: 0
    property int fetched: 0
    property int hits: 0
    property bool listed: false

    function path(url) {
        if (!url || !IC.fetchable(url))
            return "";
        const name = IC.fileName(url);
        if (known[name])
            return "file://" + dir + "/" + name;
        if (listed && !st.failed[url] && !st.active[url]) {
            st.queue = IC.enqueue(st.queue, url);
            Qt.callLater(pump);
        }
        return "";
    }

    function pump() {
        while (running < IC.MAX_PARALLEL && st.queue.length > 0) {
            const url = st.queue.shift();
            const name = IC.fileName(url);
            if (known[name] || st.active[url])
                continue;
            const proc = fetcher.createObject(root, {
                url: url,
                name: name
            });
            st.active[url] = true;
            running++;
            proc.running = true;
        }
        queued = st.queue.length;
    }

    function done(proc, ok) {
        delete st.active[proc.url];
        running--;
        if (ok) {
            known[proc.name] = true;
            fetched++;
            version++;
        } else {
            st.failed[proc.url] = true;
        }
        proc.destroy();
        pump();
    }

    Component {
        id: fetcher

        Process {
            id: p

            property string url
            property string name

            command: IC.curlArgv(url, root.dir + "/" + name)
            onExited: code => root.done(p, code === 0)
        }
    }

    // One listing at start: everything already cached is a hit without touching the network.
    Process {
        running: true
        command: ["sh", "-c", "mkdir -p \"$1\" && ls -1 \"$1\"", "ls", root.dir]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const k = {};
                for (const line of text.split("\n")) {
                    const n = line.trim();
                    if (n && n.indexOf(".part") === -1)
                        k[n] = true;
                }
                root.known = k;
                root.hits = Object.keys(k).length;
                root.listed = true;
                root.version++;
            }
        }
    }
}
