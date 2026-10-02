pragma ComponentBehavior: Bound

import QtQuick
import "../lib/format.mjs" as F

// Search tab (mockup renderSearch): filter chips (cat, kind, verdict, installed, sort),
// match info with latency, and a recycling ListView of result rows (pages of 60 on scroll).
Item {
    id: view

    property int cur: -1

    function move(dir) {
        if (dir === "down")
            cur = Math.min(Store.results.length - 1, cur + 1);
        else if (dir === "up")
            cur = Math.max(-1, cur - 1);
        if (cur >= 0)
            list.positionViewAtIndex(cur, ListView.Contain);
        if (cur >= Store.results.length - 10)
            Store.more();
    }

    function page(d) {
        cur = Math.max(0, Math.min(Store.results.length - 1, cur + d * 10));
        list.positionViewAtIndex(cur, ListView.Contain);
        if (cur >= Store.results.length - 10)
            Store.more();
    }

    function current() {
        return cur >= 0 ? Store.results[cur] || null : null;
    }

    function activate() {
        const r = current();
        if (r)
            Store.open(r);
    }

    Connections {
        target: Store

        function onResultsReset() {
            view.cur = Math.min(view.cur, Store.results.length - 1);
            list.positionViewAtBeginning();
        }
    }

    Flow {
        id: bar

        x: 20
        y: 12
        width: parent.width - 40
        spacing: 6

        Txt {
            text: "CAT"
            size: 10
            color: Theme.muted
            height: 22
            font.letterSpacing: 1.2
        }

        Repeater {
            model: [["all", "all"]].concat(F.CATEGORIES.slice(0, 7).map(c => [c[0], c[0].toLowerCase().replace("developer tools", "dev")]))

            Chip {
                required property var modelData

                label: modelData[1]
                clickable: true
                pressed: Store.filters.cat === modelData[0]
                onClicked: Store.setFilter("cat", modelData[0])
            }
        }

        Item {
            width: 8
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
            model: [["all", "all"]].concat(F.KINDS.map(k => [k, k.toLowerCase().replace("bar widget", "widget")]))

            Chip {
                required property var modelData

                label: modelData[1]
                clickable: true
                pressed: Store.filters.kind === modelData[0]
                onClicked: Store.setFilter("kind", modelData[0])
            }
        }

        Item {
            width: 8
            height: 22
        }

        Txt {
            text: "VERDICT"
            size: 10
            color: Theme.muted
            height: 22
            font.letterSpacing: 1.2
        }

        Chip {
            label: "all"
            clickable: true
            pressed: Store.filters.verdict === "all"
            onClicked: Store.setFilter("verdict", "all")
        }

        Repeater {
            model: F.OUTCOMES

            Chip {
                required property string modelData

                tone: modelData
                icon: F.outcome(modelData).icon
                label: modelData
                clickable: true
                pressed: Store.filters.verdict === modelData
                onClicked: Store.setFilter("verdict", modelData)
            }
        }

        Item {
            width: 8
            height: 22
        }

        Chip {
            icon: "dl"
            label: "installed"
            clickable: true
            pressed: Store.filters.inst
            onClicked: Store.setFilter("inst", !Store.filters.inst)
        }

        Item {
            width: 8
            height: 22
        }

        Txt {
            text: "SORT"
            size: 10
            color: Theme.muted
            height: 22
            font.letterSpacing: 1.2
        }

        Repeater {
            model: [["rank", "rank"], ["stars", "★"], ["trending", "↑ trending"], ["new", "new"], ["updated", "updated"]]

            Chip {
                required property var modelData

                label: modelData[1]
                clickable: true
                pressed: Store.sort === modelData[0]
                onClicked: Store.setSort(modelData[0])
            }
        }
    }

    Item {
        id: info

        anchors.top: bar.bottom
        anchors.topMargin: 8
        x: 20
        width: parent.width - 40
        height: 18

        Txt {
            anchors.left: parent.left
            size: 10
            color: Theme.muted
            textFormat: Text.StyledText
            text: (Store.words.length ? "matches for <font color='" + Theme.text + "'><b>" + F.escapeHtml(Store.query) + "</b></font>" : "all plugins") + " · " + F.int(Store.resultCount) + " of " + F.int(Store.total) + " · " + F.ms(Store.resultMs) + " ms in the search worker"
        }

        Txt {
            anchors.right: parent.right
            size: 10
            color: Theme.muted
            text: Store.indexed ? "budget <5 ms per keystroke over " + F.int(Store.total) + " · ListView recycles rows" : "building index…"
        }
    }

    Item {
        id: head

        anchors.top: info.bottom
        anchors.topMargin: 4
        x: 20
        width: parent.width - 40
        height: 20

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Theme.borderStrong
        }

        Txt {
            x: 92
            text: "PLUGIN"
            size: 10
            color: Theme.muted
            font.letterSpacing: 1.2
        }

        Txt {
            x: head.width - 280
            text: "KIND · CAT"
            size: 10
            color: Theme.muted
            font.letterSpacing: 1.2
        }

        Txt {
            x: head.width - 150
            width: 70
            horizontalAlignment: Text.AlignRight
            text: "★"
            size: 10
            color: Theme.muted
        }

        Txt {
            x: head.width - 70
            width: 40
            horizontalAlignment: Text.AlignRight
            text: "RANK"
            size: 10
            color: Theme.muted
            font.letterSpacing: 1.2
        }
    }

    ListView {
        id: list

        anchors.top: head.bottom
        anchors.bottom: parent.bottom
        x: 20
        width: parent.width - 40
        clip: true
        model: Store.results
        cacheBuffer: 600
        boundsBehavior: Flickable.StopAtBounds
        onAtYEndChanged: if (atYEnd)
            Store.more()

        delegate: ResultRow {
            required property var modelData
            required property int index

            width: list.width
            rec: modelData
            current: index === view.cur
            onActivated: Store.open(modelData)
        }

        footer: Txt {
            width: list.width
            height: 40
            horizontalAlignment: Text.AlignHCenter
            size: 11
            color: Theme.muted
            text: Store.resultCount === 0 && Store.shownSeq > 0 ? "no plugin matches. try fewer words or clear a filter." : Store.results.length < Store.resultCount ? "showing " + Store.results.length + " of " + F.int(Store.resultCount) + " · scroll loads more" : ""
        }
    }
}
