pragma ComponentBehavior: Bound

import QtQuick
import "../lib/format.mjs" as F
import "../lib/nav.mjs" as Nav

// Browse tab (mockup renderCats): category chips + kind chips; "all" shows the category
// grid and three category shelves; a category shows its top 30 by rank in a 6-column grid.
Item {
    id: view

    property var cur: null
    readonly property bool all: Store.browseCat === "all"
    readonly property var d: Store.data
    readonly property int cols: 6
    readonly property real cellW: (width - 40 - (cols - 1) * 10) / cols

    function rows() {
        return all ? Nav.gridRows(F.CATEGORIES.length, cols) : Nav.gridRows(Store.browseRows.length, cols);
    }

    function move(dir) {
        cur = Nav.move(rows(), cur, dir, false);
        if (!all && cur)
            grid.positionViewAtIndex(cur.r * cols + cur.c, GridView.Contain);
    }

    function current() {
        if (!cur || all)
            return null;
        return Store.browseRows[cur.r * cols + cur.c] || null;
    }

    function activate() {
        if (!cur)
            return;
        if (all) {
            const c = F.CATEGORIES[cur.r * cols + cur.c];
            if (c) {
                cur = null;
                Store.openCat(c[0]);
            }
            return;
        }
        const r = current();
        if (r)
            Store.open(r);
    }

    Flow {
        id: bar

        x: 20
        y: 12
        width: parent.width - 40
        spacing: 6

        Txt {
            text: "BROWSE"
            size: 10
            color: Theme.muted
            height: 22
            font.letterSpacing: 1.2
        }

        Repeater {
            model: F.CATEGORIES

            Chip {
                required property var modelData

                icon: modelData[1]
                label: modelData[0].toLowerCase()
                count: F.int(view.d && view.d.catCounts ? view.d.catCounts[modelData[0]] || 0 : 0)
                clickable: true
                pressed: Store.browseCat === modelData[0]
                onClicked: {
                    view.cur = null;
                    Store.openCat(modelData[0]);
                }
            }
        }

        Item {
            width: 12
            height: 22
        }

        Txt {
            text: "KIND"
            size: 10
            color: Theme.muted
            height: 22
            font.letterSpacing: 1.2
        }

        Repeater {
            model: F.KINDS

            Chip {
                required property string modelData

                label: modelData.toLowerCase()
                clickable: true
                pressed: Store.filters.kind === modelData
                onClicked: Store.setFilter("kind", Store.filters.kind === modelData ? "all" : modelData)
            }
        }
    }

    Flickable {
        visible: view.all
        anchors.top: bar.bottom
        anchors.topMargin: 8
        anchors.bottom: parent.bottom
        width: parent.width
        contentHeight: allCol.height + 24
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: allCol

            width: parent.width

            Grid {
                x: 20
                columns: view.cols
                spacing: 8

                Repeater {
                    model: F.CATEGORIES

                    CatTile {
                        required property var modelData
                        required property int index

                        width: (view.width - 40 - 8 * (view.cols - 1)) / view.cols
                        name: modelData[0]
                        suffix: " plugins"
                        count: view.d && view.d.catCounts ? view.d.catCounts[modelData[0]] || 0 : 0
                        current: view.cur !== null && view.cur.r * view.cols + view.cur.c === index
                        onActivated: Store.openCat(modelData[0])
                    }
                }
            }

            Shelf {
                key: "top"
                title: "top in widgets"
                icon: "widget"
                why: "by rank"
                items: view.d && view.d.byCategory.Widgets ? view.d.byCategory.Widgets : []
                onOpen: r => Store.open(r)
            }

            Shelf {
                key: "top"
                title: "top in productivity"
                icon: "task"
                why: "by rank"
                items: view.d && view.d.byCategory.Productivity ? view.d.byCategory.Productivity : []
                onOpen: r => Store.open(r)
            }

            Shelf {
                key: "top"
                title: "top in developer tools"
                icon: "code"
                why: "by rank"
                items: view.d && view.d.byCategory["Developer Tools"] ? view.d.byCategory["Developer Tools"] : []
                onOpen: r => Store.open(r)
            }
        }
    }

    Item {
        visible: !view.all
        anchors.top: bar.bottom
        anchors.topMargin: 12
        anchors.bottom: parent.bottom
        width: parent.width

        Item {
            id: catHead

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
                    text: Store.browseCat.toLowerCase()
                    size: 13
                    weight: Font.DemiBold
                }

                Txt {
                    text: "top " + Store.browseRows.length + " of " + F.int(view.d && view.d.catCounts ? view.d.catCounts[Store.browseCat] || 0 : 0) + " by rank · GridView, " + view.cols + " columns"
                    size: 10
                    color: Theme.muted
                }
            }

            Txt {
                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                text: "all categories"
                size: 11
                color: Theme.muted

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        view.cur = null;
                        Store.browseCat = "all";
                    }
                }
            }
        }

        GridView {
            id: grid

            anchors.top: catHead.bottom
            anchors.topMargin: 10
            anchors.bottom: parent.bottom
            x: 20
            width: parent.width - 30
            cellWidth: view.cellW + 10
            cellHeight: Math.round(view.cellW * 9 / 16) + 76
            clip: true
            cacheBuffer: 2 * cellHeight
            boundsBehavior: Flickable.StopAtBounds
            model: Store.browseRows

            delegate: Card {
                required property var modelData
                required property int index

                width: view.cellW
                rec: modelData
                current: view.cur !== null && view.cur.r * view.cols + view.cur.c === index
                onActivated: Store.open(modelData)
            }
        }
    }
}
