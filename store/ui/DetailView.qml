pragma ComponentBehavior: Bound

import QtQuick
import "../lib/format.mjs" as F
import "../lib/install.mjs" as Inst
import "../lib/rank.mjs" as Rank

// Plugin detail (mockup renderDetail): sticky header, section tabs (overview, security,
// tech, deps, activity; o s x d a), main column + 320px aside. The full report is loaded
// lazily (Store.loadDetail); unreviewed plugins show what the snapshot knows.
Item {
    id: view

    readonly property var r: Store.rec || ({})
    readonly property var d: Store.detail
    readonly property bool reviewed: r.verdict !== "unreviewed"
    readonly property real mainW: width - 40 - 320 - 16
    readonly property var oc: F.outcome(r.verdict)
    readonly property string sec: Store.section
    readonly property var crit: r.criteria || (d ? d.criteria || null : null)
    readonly property bool installable: Inst.command(r) !== null
    // Marketplace preview first, then README images (detail document listing.gallery).
    readonly property var shots: (r.full ? [r.full] : []).concat((r.gallery || []).filter(u => u !== r.full)).slice(0, 6)

    function move(dir) {
        body.contentY = Math.max(0, Math.min(body.contentHeight - body.height, body.contentY + (dir === "down" ? 80 : dir === "up" ? -80 : 0)));
    }

    function page(dlt) {
        body.contentY = Math.max(0, Math.min(body.contentHeight - body.height, body.contentY + dlt * body.height * 0.8));
    }

    function current() {
        return Store.rec;
    }

    function activate() {
    }

    onSecChanged: body.contentY = 0

    // ---- header ----------------------------------------------------------------------
    Rectangle {
        id: dhead

        width: parent.width
        height: 97
        color: Theme.bgDeep
        z: 2

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Theme.borderSubtle
        }

        Thumb {
            x: 20
            anchors.verticalCenter: parent.verticalCenter
            width: 64
            height: 64
            url: view.r.thumb || ""
            ini: view.r.ini || ""
            hint: false
            accent: F.accentFor(view.r.id || "", view.r.accent)
        }

        Column {
            x: 98
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 98 - actions.width - 40
            spacing: 6

            Row {
                spacing: 10
                width: parent.width

                Txt {
                    text: view.r.name || ""
                    size: 20
                    weight: Font.DemiBold
                    font.letterSpacing: -0.6
                    width: Math.min(implicitWidth, parent.width - 220)
                }

                Glyph {
                    outcome: view.r.verdict || "unreviewed"
                    size: 16
                    anchors.verticalCenter: parent.verticalCenter
                }

                Txt {
                    text: view.r.id || ""
                    size: 10
                    color: Theme.muted
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Flow {
                width: parent.width
                spacing: 12

                Txt {
                    text: view.r.author || ""
                    size: 11
                    color: Theme.textSecondary
                    weight: Font.Medium
                }

                Row {
                    spacing: 4

                    Ico {
                        name: "star"
                        size: 11
                    }

                    Txt {
                        text: F.int(view.r.stars)
                        size: 11
                        color: Theme.textSecondary
                    }
                }

                Item {
                    width: rkRow.implicitWidth
                    height: rkRow.implicitHeight

                    Row {
                        id: rkRow

                        spacing: 4

                        Ico {
                            name: "rank"
                            size: 11
                        }

                        Txt {
                            text: view.r.rank ? "#" + view.r.rank : "unranked"
                            size: 11
                            color: Theme.textSecondary
                        }

                        Kbd {
                            label: "?"
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Store.rankDialog(view.r)
                    }
                }

                Txt {
                    text: view.r.cat || ""
                    size: 11
                    color: Theme.muted
                }

                Txt {
                    text: view.r.kind || ""
                    size: 11
                    color: Theme.muted
                }

                Txt {
                    text: view.r.verif === "verified" ? "✓ verified listing" : "unverified listing"
                    size: 11
                    color: view.r.verif === "verified" ? Theme.green : Theme.muted
                }

                Txt {
                    visible: !!view.r.license
                    text: view.r.license || ""
                    size: 11
                    color: Theme.muted
                }

                Txt {
                    visible: !!view.r.version
                    text: "v" + (view.r.version || "")
                    size: 11
                    color: Theme.muted
                }
            }
        }

        InstallButton {
            id: actions

            anchors.right: parent.right
            anchors.rightMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            rec: view.r
        }
    }

    // ---- section tabs ------------------------------------------------------------------
    Item {
        id: dnav

        anchors.top: dhead.bottom
        width: parent.width
        height: 40
        z: 2

        Rectangle {
            anchors.fill: parent
            color: Theme.bg
        }

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Theme.borderSubtle
        }

        Row {
            x: 20
            anchors.bottom: parent.bottom
            spacing: 2

            Repeater {
                model: [["overview", "info", "o"], ["security", "shield", "s"], ["tech", "bot", "x"], ["deps", "layers", "d"], ["activity", "commit", "a"]]

                Item {
                    id: tabItem

                    required property var modelData
                    readonly property bool on: Store.section === modelData[0]

                    width: tabRow.implicitWidth + 20
                    height: 30

                    Row {
                        id: tabRow

                        anchors.centerIn: parent
                        spacing: 6

                        Ico {
                            name: tabItem.modelData[1]
                            size: 12
                            color: tabItem.on ? Theme.text : Theme.muted
                        }

                        Txt {
                            text: tabItem.modelData[0]
                            size: 11
                            weight: Font.Medium
                            color: tabItem.on ? Theme.text : Theme.muted
                        }
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 2
                        color: tabItem.on ? Theme.brand : "transparent"
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Store.section = tabItem.modelData[0]
                    }
                }
            }
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 20
            anchors.bottom: parent.bottom
            height: 30
            spacing: 4

            Repeater {
                model: [["marketplace", "https://plugins.omarchy.org/plugin.html?id=" + encodeURIComponent(view.r.id || "")], ["repo", view.r.repo || ""]]

                Row {
                    id: lnk

                    required property var modelData

                    visible: modelData[1] !== ""
                    spacing: 5
                    anchors.verticalCenter: parent.verticalCenter
                    leftPadding: 8
                    rightPadding: 8

                    Ico {
                        name: "ext"
                        size: 11
                        color: Theme.blue
                    }

                    Txt {
                        text: lnk.modelData[0]
                        size: 11
                        color: Theme.blue

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Qt.openUrlExternally(lnk.modelData[1])
                        }
                    }
                }
            }
        }
    }

    // ---- body --------------------------------------------------------------------------
    Flickable {
        id: body

        anchors.top: dnav.bottom
        anchors.bottom: parent.bottom
        width: parent.width
        contentHeight: Math.max(mainCol.height, aside.height) + 32
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: mainCol

            x: 20
            y: 16
            width: view.mainW
            spacing: 16

            // overview -------------------------------------------------------------------
            Column {
                visible: view.sec === "overview"
                width: parent.width
                spacing: 6

                Rectangle {
                    width: parent.width
                    height: Math.round(width * 9 / 16)
                    color: Theme.bgDeep
                    border.color: Theme.borderSubtle
                    border.width: 1

                    Thumb {
                        anchors.fill: parent
                        anchors.margins: 1
                        url: view.shots[Store.gallery] || view.r.full || ""
                        ini: view.r.ini || ""
                        iniSize: 48
                        accent: F.accentFor(view.r.id || "", view.r.accent)
                    }
                }

                Row {
                    width: parent.width
                    spacing: 6

                    Repeater {
                        model: view.shots

                        Rectangle {
                            required property int index
                            required property string modelData

                            width: 96
                            height: 54
                            color: Theme.bgDeep
                            border.color: Store.gallery === index ? Theme.brand : Theme.borderSubtle
                            border.width: 1

                            Thumb {
                                anchors.fill: parent
                                anchors.margins: 1
                                small: true
                                url: parent.index === 0 && view.r.full ? (view.r.thumb || parent.modelData) : parent.modelData
                                ini: view.r.ini || ""
                                accent: F.accentFor(view.r.id || "", view.r.accent)
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: Store.gallery = parent.index
                            }
                        }
                    }

                    Txt {
                        width: parent.width - 102 * view.shots.length - 6
                        height: 54
                        horizontalAlignment: Text.AlignRight
                        verticalAlignment: Text.AlignBottom
                        text: view.shots.length === 0 ? "no preview → initials tile" : (view.r.full ? "marketplace preview" : "") + ((view.r.gallery || []).length ? (view.r.full ? " + " : "") + (view.r.gallery || []).length + " readme image(s)" : "") + " · cached in ~/.cache/omarchy-plugin-check/img"
                        size: 10
                        color: Theme.muted
                    }
                }
            }

            Box {
                visible: view.sec === "overview"
                width: parent.width
                title: "description"
                icon: "info"
                note: "from plugins.omarchy.org"
                titleSize: 12

                Txt {
                    width: Math.min(parent.width, 620)
                    text: view.r.desc || ""
                    color: Theme.textSecondary
                    wrapMode: Text.Wrap
                    elide: Text.ElideNone
                    lineHeight: 1.25
                }

                Flow {
                    width: parent.width
                    spacing: 6

                    Repeater {
                        model: view.r.tags || []

                        Chip {
                            required property string modelData

                            icon: "tag"
                            label: modelData
                        }
                    }
                }
            }

            Box {
                visible: view.sec === "overview" || view.sec === "security"
                width: parent.width
                title: view.sec === "security" ? "combined verdict" : "verdict"
                icon: "shield"
                note: view.sec === "security" ? "worst of core + verified · community & unsigned ≤ caution" : "combined · worst of trusted"
                titleSize: 12

                Rectangle {
                    width: parent.width
                    height: comb.implicitHeight + 24
                    color: Theme.surface2

                    Rectangle {
                        width: 3
                        height: parent.height
                        color: Theme.c(view.oc.color)
                    }

                    Column {
                        id: comb

                        x: 17
                        y: 12
                        width: parent.width - 31
                        spacing: 8

                        Row {
                            spacing: 14

                            Row {
                                spacing: 8

                                Glyph {
                                    outcome: view.r.verdict || "unreviewed"
                                    size: 20
                                }

                                Txt {
                                    text: view.r.verdict || ""
                                    size: 18
                                    weight: Font.DemiBold
                                    color: Theme.c(view.oc.color)
                                }
                            }

                            Meter {
                                visible: view.r.risk !== null && view.r.risk !== undefined
                                value: view.r.risk || 0
                                tint: Theme.c(view.oc.color)
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Txt {
                                anchors.verticalCenter: parent.verticalCenter
                                size: 11
                                color: Theme.muted
                                text: !view.reviewed ? "no provider has reviewed this commit" : view.sec === "security" ? "reviewed commit " + F.shortSha(view.r.commit) + " · " + (view.d ? view.d.reviewedAt : "") : (Store.meta.providers || []).map(p => (p.id === "marketplace" ? "mkt" : p.id) + " " + p.tier).join(" · ")
                            }
                        }

                        CritChips {
                            width: parent.width
                            criteria: view.crit
                        }
                    }
                }

                Flow {
                    visible: view.sec === "security" && !!view.d && !!view.d.hardFails && view.d.hardFails.length > 0
                    width: parent.width
                    spacing: 4

                    Txt {
                        text: "HARD-FAILS"
                        size: 10
                        color: Theme.muted
                        height: 22
                    }

                    Repeater {
                        model: view.d && view.d.hardFails ? view.d.hardFails : []

                        Chip {
                            required property string modelData

                            tone: "hf"
                            icon: "x"
                            label: modelData
                        }
                    }
                }

                Txt {
                    visible: view.sec === "overview" && !!view.d && (view.d.ai || view.d.oneLiner) !== ""
                    width: parent.width
                    textFormat: Text.StyledText
                    text: "<font color='" + Theme.blue + "'>" + F.ICON.bot + "</font> " + F.escapeHtml(view.d ? (view.d.oneLiner || view.d.ai) : "")
                    color: Theme.textSecondary
                    wrapMode: Text.Wrap
                    elide: Text.ElideNone
                }
            }

            // security -------------------------------------------------------------------
            Box {
                visible: view.sec === "security"
                width: parent.width
                title: "providers"
                icon: "users"
                note: "each row = one report"
                titleSize: 12
                spacing: 0

                Repeater {
                    model: view.d ? view.d.providers : []

                    ProviderRow {
                        required property var modelData

                        width: parent.width
                        row: modelData
                    }
                }

                ProviderRow {
                    visible: !view.d
                    width: parent.width
                    row: null
                    listed: view.r.listed || ""
                }
            }

            Box {
                visible: view.sec === "security" && !!view.d && !!view.d.findings && view.d.findings.length > 0
                width: parent.width
                title: "evidence"
                icon: "flag"
                note: view.d && view.d.findingCount ? "top " + Math.min(12, view.d.findingCount) + " of " + view.d.findingCount + " findings · path:line" : ""
                titleSize: 12

                Table {
                    width: parent.width
                    head: ["sev", "finding", "where"]
                    widths: [70, parent.width - 70 - 200, 200]
                    rows: view.d && view.d.findings ? view.d.findings.map(f => [f.sev, f.msg, f.where]) : []
                    chipCol: 0
                }
            }

            // tech -----------------------------------------------------------------------
            Box {
                visible: view.sec === "tech"
                width: parent.width
                title: view.d && view.d.hasReport ? "ai analysis" : view.reviewed ? "full report not in this snapshot" : "not reviewed yet"
                icon: "bot"
                note: view.d && view.d.hasReport ? "escalate-only · " + (view.d.aiModel || "no ai") + (view.d.guardOk ? " · guard ok" : "") : ""
                titleSize: 12

                Txt {
                    width: parent.width
                    text: view.d && view.d.hasReport ? (view.d.ai || view.d.summary) : view.reviewed ? "Capabilities, hosts, dependencies and performance come with the provider's full report, which this snapshot's API does not carry yet. Verdict and evidence are on the security tab." : "Listed " + F.ago(view.r.listed, Date.now()) + " ago. New listings are scanned within 24–72 h; nothing to show until a provider publishes a report."
                    color: Theme.textSecondary
                    wrapMode: Text.Wrap
                    elide: Text.ElideNone
                    lineHeight: 1.25
                }
            }

            Box {
                visible: view.sec === "tech" && !!view.d && view.d.hasReport
                width: parent.width
                title: "capabilities"
                icon: "exec"
                note: "from static scan, ground truth"
                titleSize: 12

                Row {
                    spacing: 4

                    Repeater {
                        model: F.CAPS

                        Rectangle {
                            id: cap

                            required property var modelData
                            readonly property string lvl: view.d && view.d.caps ? F.capLevel(view.d.caps[modelData[0]]) : "none"

                            width: 30
                            height: 30
                            color: Theme.bgDeep
                            opacity: lvl === "none" ? 0.3 : 1
                            border.width: 1
                            border.color: lvl === "high" ? Theme.red : lvl === "med" ? Theme.yellow : lvl === "low" ? Theme.borderStrong : Theme.borderSubtle

                            Ico {
                                anchors.centerIn: parent
                                name: cap.modelData[1]
                                size: 15
                                color: cap.lvl === "high" ? Theme.red : cap.lvl === "med" ? Theme.yellow : Theme.textSecondary
                            }

                            HoverHandler {
                                id: capHover
                            }

                            Tip {
                                shown: capHover.hovered
                                label: cap.modelData[2] + ": " + cap.lvl
                            }
                        }
                    }
                }

                Txt {
                    width: parent.width
                    text: "none · low · med · high     exec · net · write · persist · priv · pkg · binary · clipboard · capture · hypr ipc"
                    size: 10
                    color: Theme.muted
                }
            }

            Row {
                visible: view.sec === "tech" && !!view.d && view.d.hasReport
                width: parent.width
                spacing: 16

                Box {
                    width: (parent.width - 16) / 2
                    title: "system areas"
                    icon: "layers"
                    titleSize: 12

                    Flow {
                        width: parent.width
                        spacing: 4

                        Repeater {
                            model: view.d && view.d.areas ? view.d.areas : []

                            Chip {
                                required property string modelData

                                label: modelData
                                tone: /write|sudo|ssh|systemd|exec-once|rc/.test(modelData) ? "caution" : ""
                            }
                        }

                        Txt {
                            visible: !view.d || !view.d.areas || view.d.areas.length === 0
                            text: "none outside the shell"
                            size: 11
                            color: Theme.muted
                        }
                    }
                }

                Box {
                    width: (parent.width - 16) / 2
                    title: "network hosts"
                    icon: "net"
                    titleSize: 12

                    Repeater {
                        model: view.d && view.d.hosts ? view.d.hosts.slice(0, 8) : []

                        Row {
                            id: hostRow

                            required property var modelData

                            spacing: 8

                            Txt {
                                text: hostRow.modelData.host
                                size: 11
                            }

                            Txt {
                                text: hostRow.modelData.schemes
                                size: 10
                                color: Theme.muted
                            }
                        }
                    }

                    Txt {
                        visible: !view.d || !view.d.hosts || view.d.hosts.length === 0
                        text: "no outbound hosts"
                        size: 11
                        color: Theme.muted
                    }
                }
            }

            Box {
                visible: view.sec === "tech" && !!view.d && view.d.hasReport
                width: parent.width
                title: "performance"
                icon: "perf"
                note: "timers, spawns, memory"
                titleSize: 12

                StatRow {
                    width: parent.width
                    cells: view.d && view.d.perf ? [[view.d.perf.timers + " timers", view.d.perf.minInterval ? "fastest " + (view.d.perf.minInterval < 1000 ? view.d.perf.minInterval + " ms" : Math.round(view.d.perf.minInterval / 1000) + " s") : "no repeat"], [(view.d.perf.spawns === null ? "—" : view.d.perf.spawns) + "/min", "process spawns"], ["keepLoaded: " + (view.d.perf.keepLoaded ? "yes" : "no"), "manifest"], [view.d.perf.largeAssets + " large", "assets"]] : []
                }
            }

            // deps -----------------------------------------------------------------------
            Box {
                visible: view.sec === "deps"
                width: parent.width
                title: "libraries & dependencies"
                icon: "layers"
                note: "osv-scanner · guarddog · lockfiles"
                titleSize: 12

                Table {
                    width: parent.width
                    head: ["package", "version", "ecosystem", "advisories"]
                    widths: [parent.width * 0.4, parent.width * 0.2, parent.width * 0.15, parent.width * 0.25]
                    rows: view.d && view.d.deps && view.d.deps.length ? view.d.deps.slice(0, 40).map(x => [x.name, x.version, x.eco, x.adv || "—"]) : [[view.d && view.d.hasReport ? "no declared dependencies" : "no reports yet", "", "", ""]]
                    chipCol: 2
                }

                Row {
                    spacing: 6

                    Txt {
                        text: "ECOSYSTEMS"
                        size: 10
                        color: Theme.muted
                        height: 22
                    }

                    Repeater {
                        model: view.d && view.d.ecosystems ? view.d.ecosystems : []

                        Chip {
                            required property string modelData

                            label: modelData
                        }
                    }

                    Txt {
                        text: "   PINNING"
                        size: 10
                        color: Theme.muted
                        height: 22
                    }

                    Chip {
                        tone: view.d && view.d.supply && view.d.supply.unpinned > 0 ? "caution" : "safe"
                        label: view.d && view.d.supply ? (view.d.supply.unpinned > 0 ? view.d.supply.unpinned + " unpinned remote" : "all pinned") : "—"
                    }
                }
            }

            // activity -------------------------------------------------------------------
            Box {
                visible: view.sec === "activity"
                width: parent.width
                title: "commits · 52 weeks"
                icon: "commit"
                note: view.d && view.d.weeks && view.d.weeks.some(w => w === null) ? "github · last 100 commits (older weeks unknown)" : "github graphql · nightly collector"
                titleSize: 12

                Sparkline {
                    width: parent.width
                    values: view.d && view.d.weeks ? view.d.weeks : []
                    visible: values.length > 1
                }

                Txt {
                    visible: !view.d || !view.d.weeks || view.d.weeks.length < 2
                    text: "weekly series arrives with the plugin's full report"
                    size: 11
                    color: Theme.muted
                }

                StatRow {
                    width: parent.width
                    cells: [[view.r.c90 === null || view.r.c90 === undefined ? "—" : String(view.r.c90), "commits 90d"], [(view.r.contrib || "—") + "  bus " + (view.r.bus || "—"), "contributors"], [view.r.lastRelease || ((view.r.rel180 || 0) + " tags"), "releases"], [F.hours(view.r.respH), "issue response"]]
                }
            }

            Box {
                visible: view.sec === "activity"
                width: parent.width
                title: "why #" + (view.r.rank || "—")
                icon: "rank"
                note: "open ranking · weights are placeholders until docs/RANKING.md"
                titleSize: 12

                Repeater {
                    model: Rank.explain(view.r, Store.meta.factors, Date.now())

                    Item {
                        id: fb

                        required property var modelData

                        width: parent.width
                        height: 14

                        Txt {
                            width: 150
                            text: fb.modelData.label + "  w" + fb.modelData.weight
                            size: 11
                            color: Theme.textSecondary
                        }

                        Rectangle {
                            x: 160
                            width: parent.width - 160 - 54
                            height: 10
                            anchors.verticalCenter: parent.verticalCenter
                            color: Qt.alpha(Theme.blue, 0.14)

                            Rectangle {
                                width: Math.max(1, fb.modelData.pct * parent.width)
                                height: parent.height
                                color: Theme.blue
                            }

                            HoverHandler {
                                id: fbHover
                            }

                            Tip {
                                shown: fbHover.hovered
                                label: fb.modelData.detail
                            }
                        }

                        Txt {
                            anchors.right: parent.right
                            width: 44
                            horizontalAlignment: Text.AlignRight
                            text: Number(fb.modelData.value).toFixed(1)
                            size: 11
                            color: Theme.textSecondary
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: 14

                    Txt {
                        width: 150
                        text: "safety gate  ×" + Rank.gateOf(view.r.verdict)
                        size: 11
                        color: Theme.textSecondary
                    }

                    Rectangle {
                        x: 160
                        width: parent.width - 160 - 54
                        height: 10
                        anchors.verticalCenter: parent.verticalCenter
                        color: Qt.alpha(Theme.orange, 0.14)

                        Rectangle {
                            width: Rank.gateOf(view.r.verdict) * parent.width
                            height: parent.height
                            color: Theme.orange
                        }
                    }

                    Txt {
                        anchors.right: parent.right
                        width: 44
                        horizontalAlignment: Text.AlignRight
                        text: view.r.rankScore === null || view.r.rankScore === undefined ? "—" : Number(view.r.rankScore).toFixed(1)
                        size: 11
                        color: Theme.textSecondary
                    }
                }

                Btn {
                    sm: true
                    icon: "info"
                    label: "explain"
                    key: "?"
                    onClicked: Store.rankDialog(view.r)
                }
            }

            Txt {
                visible: Store.detailLoading
                text: "loading report…"
                size: 11
                color: Theme.muted
            }
        }

        // ---- aside ---------------------------------------------------------------------
        Column {
            id: aside

            x: 20 + view.mainW + 16
            y: 16
            width: 320
            spacing: 12

            Box {
                width: parent.width
                title: "install"
                icon: "dl"

                Txt {
                    visible: view.r.verdict === "blocked"
                    width: parent.width
                    text: "install is refused. --force is not honored for blocked plugins."
                    size: 11
                    color: Theme.red
                    wrapMode: Text.Wrap
                }

                Rectangle {
                    visible: view.r.verdict !== "blocked" && view.installable
                    width: parent.width
                    height: cmd.implicitHeight + 12
                    color: Theme.bgDeep
                    border.color: Theme.borderSubtle
                    border.width: 1

                    Txt {
                        id: cmd

                        x: 8
                        y: 6
                        width: parent.width - 16
                        text: "omarchy-plugin-check --add --pin \\\n  " + (view.r.repo || "")
                        size: 10
                        color: Theme.textSecondary
                        wrapMode: Text.WrapAnywhere
                        elide: Text.ElideNone
                    }
                }

                Txt {
                    visible: view.r.verdict !== "blocked" && !view.installable
                    width: parent.width
                    text: "manual setup · not installable from the store"
                    size: 11
                    color: Theme.muted
                    wrapMode: Text.Wrap
                }

                KV {
                    readonly property string st: Installer.installedVersion >= 0 ? Installer.stateOf(view.r) : ""
                    readonly property var e: Installer.installedVersion >= 0 ? Installer.installed[view.r.id] || null : null

                    pairs: [["state", st === "" ? "not installed" : st === "ok" ? "installed · up to date" : st === "update" ? "update available" : st === "stale" ? "installed · stale" : "installed · " + st, st === "ok" ? "green" : st === "" ? "" : "blue"]].concat(e ? [["pinned", e.sha]] : []).concat([["reviewed", view.r.commit ? F.shortSha(view.r.commit) + " · " + (view.d ? view.d.reviewedAt : "") : "—"], ["upstream", "pushed " + F.ago(view.r.updated, Date.now()) + " ago"], ["checker", Installer.checker ? "installed" : Installer.dev ? "fake runner (--dev)" : "not installed", Installer.checker ? "green" : "yellow"]])
                }
            }

            Box {
                width: parent.width
                title: "marketplace"
                icon: "eye"

                KV {
                    pairs: [["views", F.int(view.r.views)], ["copies", F.int(view.r.copies)], ["hearts", F.int(view.r.hearts)], ["listed", F.dateOnly(view.r.listed) + " (" + F.ago(view.r.listed, Date.now()) + ")"], ["state", view.r.listingState || "—"]]
                }
            }

            Box {
                width: parent.width
                title: "images"
                icon: "img"

                KV {
                    pairs: [["thumb", view.r.thumb ? view.r.thumb.replace(/^https:\/\//, "") : "none → initials tile"], ["cache", view.r.thumb ? (ImageCache.version >= 0 && ImageCache.path(view.r.thumb) !== "" ? "hit" : "fetching") : "—"]]
                }
            }

            Box {
                width: parent.width
                title: "similar"
                icon: "users"

                Repeater {
                    model: Store.similar

                    Row {
                        id: simRow

                        required property var modelData

                        spacing: 8

                        Glyph {
                            outcome: simRow.modelData.verdict
                            size: 12
                        }

                        Txt {
                            text: simRow.modelData.name
                            size: 11
                            weight: Font.Medium

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Store.open(simRow.modelData)
                            }
                        }

                        Txt {
                            text: "★ " + F.int(simRow.modelData.stars)
                            size: 11
                            color: Theme.muted
                        }
                    }
                }

                Txt {
                    visible: Store.similar.length === 0
                    text: "—"
                    color: Theme.muted
                }
            }
        }
    }
}
