pragma ComponentBehavior: Bound

import QtQuick
import "../lib/format.mjs" as F
import "../lib/nav.mjs" as Nav

// Home tab (mockup renderHome): hero carousel, shelves (top, trending, safe picks, new,
// updated) and the categories row. Cursor: {r, c} over the visible rows, null = hero.
Flickable {
    id: view

    property var cur: null
    readonly property var d: Store.data
    readonly property var shelves: [sTop, sTrend, sSafe, sNew, sUpd]
    readonly property var cats: F.CATEGORIES

    contentWidth: width
    contentHeight: col.height + 24
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    // Estimated layout (hero 301 + 215 per shelf): valid before the Column has laid out.
    function nearShelf(i) {
        return contentY + height + 120 > 301 + i * 215;
    }

    function rows() {
        const out = [];
        for (const s of shelves)
            out.push(s.visible ? s.items.length : 0);
        out.push(cats.length);
        return out;
    }

    function rowItem(r) {
        return r < shelves.length ? shelves[r] : catBox;
    }

    function move(dir) {
        cur = Nav.move(rows(), cur, dir, true);
        reveal();
    }

    function reveal() {
        if (!cur) {
            contentY = 0;
            return;
        }
        const it = rowItem(cur.r);
        if (cur.r < shelves.length)
            it.reveal(cur.c);
        const top = it.y;
        const bottom = it.y + it.height;
        if (top < contentY)
            contentY = Math.max(0, top - 8);
        else if (bottom > contentY + height)
            contentY = Math.min(contentHeight - height, bottom - height + 8);
    }

    function current() {
        if (!cur)
            return Store.data ? Store.data.heroes[Store.hero] || null : null;
        if (cur.r < shelves.length)
            return shelves[cur.r].items[cur.c] || null;
        return null;
    }

    function activate() {
        if (cur && cur.r === shelves.length) {
            Store.openCat(cats[cur.c][0]);
            return;
        }
        const r = current();
        if (r)
            Store.open(r);
    }

    function stepHero(dlt) {
        const n = Store.data ? Store.data.heroes.length : 0;
        if (n)
            Store.hero = (Store.hero + dlt + n) % n;
    }

    Column {
        id: col

        width: view.width

        Hero {
            width: parent.width
            items: view.d ? view.d.heroes : []
            index: Store.hero
            focusedHero: view.cur === null
            onOpen: r => Store.open(r)
            onStep: dlt => view.stepHero(dlt)
            onPick: i => Store.hero = i
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.borderSubtle
        }

        Shelf {
            id: sTop

            near: view.nearShelf(0)
            key: "top"
            title: "top"
            icon: "rank"
            why: "by rank · blocked hidden, risky down-ranked"
            items: view.d ? view.d.shelves.top : []
            cursor: view.cur && view.cur.r === 0 ? view.cur.c : -1
            onOpen: r => Store.open(r)
        }

        Shelf {
            id: sTrend

            near: view.nearShelf(1)
            key: "trending"
            title: "trending"
            icon: "trend"
            why: "★ velocity, 30 days"
            extra: "trend"
            items: view.d ? view.d.shelves.trending : []
            cursor: view.cur && view.cur.r === 1 ? view.cur.c : -1
            onOpen: r => Store.open(r)
        }

        Shelf {
            id: sSafe

            near: view.nearShelf(2)
            key: "safePicks"
            title: "safe picks"
            icon: "safe"
            why: "combined verdict safe · 2+ providers"
            items: view.d ? view.d.shelves.safePicks : []
            cursor: view.cur && view.cur.r === 2 ? view.cur.c : -1
            onOpen: r => Store.open(r)
        }

        Shelf {
            id: sNew

            near: view.nearShelf(3)
            key: "new"
            title: "new"
            icon: "new"
            why: "listed on the marketplace"
            extra: "new"
            items: view.d ? view.d.shelves["new"] : []
            cursor: view.cur && view.cur.r === 3 ? view.cur.c : -1
            onOpen: r => Store.open(r)
        }

        Shelf {
            id: sUpd

            near: view.nearShelf(4)
            key: "updated"
            title: "updated"
            icon: "up"
            why: "repository push"
            extra: "upd"
            items: view.d ? view.d.shelves.updated : []
            cursor: view.cur && view.cur.r === 4 ? view.cur.c : -1
            onOpen: r => Store.open(r)
        }

        Column {
            id: catBox

            width: parent.width
            topPadding: 14
            spacing: 8

            Item {
                width: parent.width
                height: 21

                Row {
                    x: 20
                    spacing: 10
                    anchors.verticalCenter: parent.verticalCenter

                    Ico {
                        name: "grid"
                        size: 13
                        color: Theme.text
                    }

                    Txt {
                        text: "categories"
                        size: 13
                        weight: Font.DemiBold
                    }

                    Txt {
                        text: "marketplace vocabulary · counts from the snapshot"
                        size: 10
                        color: Theme.muted
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 20
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Txt {
                        text: "browse"
                        size: 11
                        color: Theme.muted
                    }

                    Kbd {
                        label: "3"
                    }
                }
            }

            Grid {
                x: 20
                columns: 9
                spacing: 8

                Repeater {
                    model: view.cats

                    CatTile {
                        required property var modelData
                        required property int index

                        width: (view.width - 40 - 8 * 8) / 9
                        height: 56
                        name: modelData[0]
                        count: view.d && view.d.catCounts ? (view.d.catCounts[modelData[0]] || 0) : 0
                        current: view.cur !== null && view.cur.r === view.shelves.length && view.cur.c === index
                        onActivated: Store.openCat(modelData[0])
                    }
                }
            }
        }
    }

    Txt {
        visible: !Store.data
        anchors.centerIn: parent
        text: Store.verifyError !== "" ? "snapshot refused · " + Store.verifyError : Store.snapshotMissing ? "no snapshot found · run omarchy-plugin-check update" : "loading snapshot…"
        color: Theme.muted
    }
}
