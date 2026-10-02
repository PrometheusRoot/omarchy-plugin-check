pragma ComponentBehavior: Bound

import QtQuick
import "../lib/format.mjs" as F

// Status tab (mockup renderStatus): snapshot, image cache, providers, performance (measured
// in this session), appearance, keys.
Flickable {
    id: view

    readonly property var m: Store.meta || ({})
    readonly property var c: Store.data ? Store.data.counts : ({})
    readonly property var t: Store.timings
    readonly property real colW: (width - 40 - 24) / 3

    contentHeight: grid.height + 32
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    function move(dir) {
        contentY = Math.max(0, Math.min(contentHeight - height, contentY + (dir === "down" ? 60 : dir === "up" ? -60 : 0)));
    }

    function current() {
        return null;
    }

    function activate() {
    }

    Component.onCompleted: if (!Store.bench && Store.indexed)
        Store.runBench()

    Connections {
        target: Store

        function onIndexedChanged() {
            if (Store.indexed && Store.tab === "status" && !Store.bench)
                Store.runBench();
        }
    }

    Grid {
        id: grid

        x: 20
        y: 16
        columns: 3
        spacing: 12

        Box {
            width: view.colW
            title: "snapshot"
            icon: "snap"

            KV {
                pairs: [["bundle", Store.usingDev ? "bundled dev data · not verified" : "manifest verified · ed25519 + sha256" + (view.m.dev ? " (DEV key)" : ""), Store.usingDev || view.m.dev ? "yellow" : "green"], ["path", Store.snapshotPath.replace(Store.home, "~")], ["catalog", F.dateOnly(view.m.catalogAt) + " · " + F.int(Store.total) + " plugins · " + F.int(view.c.images) + " with preview"], ["reports", (Store.total - (view.c.unreviewed || 0)) + " reviewed · " + (view.c.safe || 0) + " safe · " + (view.c.caution || 0) + " caution · " + (view.c.risky || 0) + " risky · " + (view.c.blocked || 0) + " blocked"], ["ranking", (view.m.rankingVersion || "—") + (view.m.dev ? " · DEV snapshot" : "")], ["index", Store.indexed ? "built in " + view.t.index + " ms · prefix + substring + fuzzy" : "building…"]]
            }
        }

        Box {
            width: view.colW
            title: "image cache"
            icon: "img"

            KV {
                pairs: [["path", ImageCache.dir.replace(Store.home, "~") + "/"], ["files", F.int(ImageCache.hits + ImageCache.fetched) + " cached · " + ImageCache.fetched + " fetched now"], ["queue", ImageCache.running + " running · " + ImageCache.queued + " queued"], ["policy", "thumbs only in grids · full image on detail and hero · curl, https only"]]
            }
        }

        Box {
            width: view.colW
            title: "providers"
            icon: "shield"

            Repeater {
                model: view.m.providers || []

                Row {
                    id: prow

                    required property var modelData

                    spacing: 8

                    Rectangle {
                        width: 30
                        height: 16
                        color: Theme.bgDeep
                        border.color: Theme.brand
                        border.width: 1
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            x: 16
                            y: 2
                            width: 10
                            height: 10
                            color: Theme.brand
                        }
                    }

                    Txt {
                        text: prow.modelData.name
                        size: 11
                        color: prow.modelData.tier === "core" ? Theme.brand : Theme.textSecondary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Chip {
                        small: true
                        height: 18
                        label: prow.modelData.tier
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Txt {
                        text: prow.modelData.verification + " · " + F.int(prow.modelData.rows)
                        size: 11
                        color: Theme.muted
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            Txt {
                width: parent.width
                text: "combined = worst of core + verified · community and unsigned capped at caution"
                size: 10
                color: Theme.muted
                wrapMode: Text.Wrap
            }
        }

        Box {
            width: view.colW
            title: "performance"
            icon: "perf"
            note: "this session"

            KV {
                pairs: [["first frame", (view.t.firstFrame || "—") + " ms after " + (Store.launched ? "launch" : "qml load")], ["home", view.t.homeAt !== undefined ? view.t.homeAt + " ms (verified " + (view.t.verify !== undefined ? view.t.verify + " ms" : "— dev data") + " · home map " + view.t.homeMap + " ms)" : "—"], ["search file", view.t.parse !== undefined ? "parse " + view.t.parse + " · map " + view.t.map + " ms (worker, after first frame) · searchable " + (view.t.indexedAt || "…") + " ms" : "—"], ["search", Store.bench ? "p50 " + F.ms(Store.bench.p50) + " · p95 " + F.ms(Store.bench.p95) + " ms per keystroke (" + Store.bench.n + " keystrokes, worker)" : Store.indexed ? "measuring…" : "index pending"], ["scroll", "ListView / GridView recycle · async Image"]]
            }

            Btn {
                sm: true
                icon: "perf"
                label: "re-run search benchmark"
                enabledState: Store.indexed
                onClicked: Store.runBench()
            }
        }

        Box {
            width: view.colW
            title: "appearance"
            icon: "palette"

            KV {
                pairs: [["theme", "~/.local/state/omarchy/current/theme → " + (Theme.name || "default")], ["font", Theme.font + " 12"], ["radius", "0 · borders 1px · no shadows"]]
            }

            Btn {
                visible: Theme.dev
                sm: true
                icon: "palette"
                label: "cycle theme"
                key: "t"
                onClicked: Theme.cycle()
            }
        }

        Box {
            width: view.colW
            title: "keys"
            icon: "keys"

            Repeater {
                model: [["/", "focus search"], ["1–5", "tabs"], ["j k ↑ ↓ ← →", "move focus"], ["⏎", "open"], ["esc", "back / close"], ["i", "install focused"], ["h l", "hero slide"], ["?", "ranking explainer"], ["t", "theme (dev)"], ["o s x d a", "detail sections"]]

                Row {
                    id: keyRow

                    required property var modelData

                    spacing: 10

                    Item {
                        width: 110
                        height: 18

                        Kbd {
                            anchors.verticalCenter: parent.verticalCenter
                            label: keyRow.modelData[0]
                        }
                    }

                    Txt {
                        text: keyRow.modelData[1]
                        size: 11
                        color: Theme.textSecondary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }
}
