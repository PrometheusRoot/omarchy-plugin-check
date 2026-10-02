pragma ComponentBehavior: Bound

import QtQuick
import "../lib/format.mjs" as F
import "../lib/install.mjs" as Inst
import "../lib/rank.mjs" as Rank

// Dialog layer + toast (mockup askInstall / runInstall / rankDialog / toast).
Item {
    id: ov

    readonly property var r: Store.dialogRec || ({})
    readonly property var flow: Installer.flow
    readonly property string st: Installer.state

    // Enter in a dialog: the autofocused button (install anyway / close / open).
    function defaultAction() {
        if (Store.dialog === "install") {
            if (st === "confirm")
                Installer.confirm();
            else if (st !== "running")
                Store.closeDialog();
        } else if (Store.dialog === "remove") {
            confirmAction();
        } else {
            Store.closeDialog();
        }
    }

    function confirmAction() {
        if (Store.dialog === "install" && st === "confirm")
            Installer.confirm();
        else if (Store.dialog === "remove") {
            Installer.remove(r);
            Store.closeDialog();
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: Store.dialog !== ""
        color: Qt.alpha(Theme.bgDeep, 0.7)

        MouseArea {
            anchors.fill: parent
            onClicked: if (ov.st !== "running")
                Store.closeDialog()
        }

        // ---- install: refused ---------------------------------------------------------
        Dialog {
            anchors.centerIn: parent
            visible: Store.dialog === "install" && ov.st === "refused"
            outcome: "blocked"
            title: "install refused · " + (ov.r.name || "")
            footNote: "providers with evidence decide · mkt baseline is unsigned"

            Txt {
                width: parent.width
                textFormat: Text.StyledText
                text: F.escapeHtml(ov.r.name) + " is <font color='" + Theme.red + "'><b>blocked</b></font>: a trusted provider found hard-fail evidence with file and line. The store will not run <font color='" + Theme.text + "'>omarchy plugin add</font> for it, and <font color='" + Theme.text + "'>--force</font> is not honored."
                color: Theme.textSecondary
                wrapMode: Text.Wrap
                elide: Text.ElideNone
            }

            Txt {
                width: parent.width
                text: "think this is wrong? open a dispute on github; the plugin shows a contested badge while it is reviewed."
                size: 11
                color: Theme.muted
                wrapMode: Text.Wrap
                elide: Text.ElideNone
            }

            buttons: [
                Btn {
                    kind: "ghost"
                    label: "close"
                    key: "esc"
                    focused: true
                    onClicked: Store.closeDialog()
                },
                Btn {
                    icon: "ext"
                    label: "dispute"
                    onClicked: Qt.openUrlExternally("https://github.com/PrometheusRoot/omarchy-plugin-check/issues/new")
                }
            ]
        }

        // ---- install: unavailable ------------------------------------------------------
        Dialog {
            anchors.centerIn: parent
            visible: Store.dialog === "install" && ov.st === "unavailable"
            glyph: "alert"
            title: "can't install " + (ov.r.name || "")
            footNote: ""

            Txt {
                width: parent.width
                text: ov.flow.reason === "checker not installed" ? "The store installs through omarchy-plugin-check, which pins the reviewed commit. It is not installed on this machine yet." : "This listing has no plain GitHub repository the checker can pin; follow its README instead."
                color: Theme.textSecondary
                wrapMode: Text.Wrap
                elide: Text.ElideNone
            }

            buttons: [
                Btn {
                    kind: "ghost"
                    label: "close"
                    key: "esc"
                    focused: true
                    onClicked: Store.closeDialog()
                }
            ]
        }

        // ---- install: confirm (caution / risky / unreviewed) -----------------------------
        Dialog {
            anchors.centerIn: parent
            visible: Store.dialog === "install" && ov.st === "confirm"
            outcome: ov.r.verdict || "unreviewed"
            title: (Installer.repin ? (Installer.stateOf(ov.r) === "stale" ? "roll back " : "update ") : "install ") + (ov.r.name || "") + "?"
            footNote: Installer.repin ? "omarchy plugin update is never used: it moves to unreviewed upstream HEAD" : "you can remove it any time from installed"

            Txt {
                width: parent.width
                textFormat: Text.StyledText
                text: Installer.repin ? "Checks out the reviewed commit " + F.shortSha(ov.r.commit) + " (combined verdict <b>" + (ov.r.verdict || "unreviewed") + "</b>) after fetching the listed repository, then verifies commit and tree against the signed snapshot and rescans omarchy-shell." : ov.r.verdict === "unreviewed" ? "No provider has reviewed this commit yet. You would be running code nobody has looked at." : "Combined verdict is <font color='" + Theme.c(F.outcome(ov.r.verdict).color) + "'><b>" + ov.r.verdict + "</b></font>" + (ov.r.risk !== null && ov.r.risk !== undefined ? " (" + ov.r.risk + "/100)" : "") + ". " + (ov.r.verdict === "risky" ? "A trusted provider found a wide surface; read the findings before continuing." : "Declared capabilities go beyond a local widget; nothing hard-failed.")
                color: Theme.textSecondary
                wrapMode: Text.Wrap
                elide: Text.ElideNone
            }

            Row {
                visible: !!ov.r.criteria && (ov.r.criteria.failed || []).length > 0
                spacing: 6

                Txt {
                    text: "FAILS"
                    size: 10
                    color: Theme.muted
                    height: 20
                }

                CritChips {
                    criteria: ov.r.criteria
                    only: ov.r.criteria ? ov.r.criteria.failed : []
                }
            }

            Rectangle {
                width: parent.width
                height: cmdText.implicitHeight + 16
                color: Theme.bgDeep
                border.color: Theme.borderSubtle
                border.width: 1

                Txt {
                    id: cmdText

                    x: 10
                    y: 8
                    width: parent.width - 20
                    textFormat: Text.StyledText
                    text: Installer.repin ? F.escapeHtml((Inst.pinCommand(ov.r) || ["omarchy-plugin-check", "pin", ov.r.id]).join(" ")) + "<br><font color='" + Theme.muted + "'># fetches, checks out " + F.shortSha(ov.r.commit) + " detached, verifies commit + tree, logs to ~/.config/omarchy/CHANGES.md</font>" : F.escapeHtml((Inst.command(ov.r) || ["omarchy-plugin-check", "--add", "--pin", ov.r.repo || ov.r.id]).join(" ")) + "<br><font color='" + Theme.muted + "'># clones, pins reviewed commit " + F.shortSha(ov.r.commit) + ", enables, logs to ~/.config/omarchy/CHANGES.md</font>"
                    size: 11
                    wrapMode: Text.WrapAnywhere
                    elide: Text.ElideNone
                }
            }

            buttons: [
                Btn {
                    kind: "ghost"
                    label: "cancel"
                    key: "esc"
                    onClicked: Store.closeDialog()
                },
                Btn {
                    kind: Installer.repin ? "primary" : ov.r.verdict === "risky" ? "risky" : "caution"
                    icon: Installer.repin ? "up" : "dl"
                    label: Installer.repin ? "pin reviewed commit" : "install anyway"
                    key: "y"
                    focused: true
                    onClicked: Installer.confirm()
                }
            ]
        }

        // ---- install: progress / done / failed ------------------------------------------
        Dialog {
            anchors.centerIn: parent
            visible: Store.dialog === "install" && (ov.st === "running" || ov.st === "done" || ov.st === "failed")
            glyph: ov.st === "failed" ? "alert" : "dl"
            title: (Installer.repin ? (ov.st === "done" ? "pinned " : ov.st === "failed" ? "pin failed · " : "pinning ") : ov.st === "done" ? "installed " : ov.st === "failed" ? "install failed · " : "installing ") + (Installer.rec ? Installer.rec.name : "")
            footNote: ov.st === "running" ? (Installer.dev ? "fake runner (--dev) · " : "") + (Installer.repin ? "running omarchy-plugin-check pin" : "running omarchy-plugin-check --add --pin") : ov.st === "failed" ? "exit " + ov.flow.code : "done"

            Rectangle {
                width: parent.width
                height: 6
                color: Theme.surface2

                Rectangle {
                    width: parent.width * (ov.flow.steps.length ? ov.flow.step / ov.flow.steps.length : 0)
                    height: parent.height
                    color: ov.st === "failed" ? Theme.red : Theme.brand

                    Behavior on width {
                        NumberAnimation {
                            duration: 300
                        }
                    }
                }
            }

            Repeater {
                model: ov.flow.steps

                Row {
                    id: stepRow

                    required property string modelData
                    required property int index
                    readonly property bool doneStep: index < ov.flow.step
                    readonly property bool nowStep: index === ov.flow.step && ov.st === "running"

                    spacing: 8

                    Ico {
                        name: stepRow.doneStep ? "check" : stepRow.nowStep ? "up" : "clock"
                        size: 12
                        color: stepRow.doneStep ? Theme.green : stepRow.nowStep ? Theme.blue : Theme.muted
                    }

                    Txt {
                        text: stepRow.modelData
                        color: stepRow.doneStep || stepRow.nowStep ? Theme.text : Theme.muted
                    }
                }
            }

            Txt {
                visible: ov.flow.log.length > 0 && ov.st === "failed"
                width: parent.width
                text: ov.flow.log.join("\n")
                size: 10
                color: Theme.muted
                wrapMode: Text.WrapAnywhere
                elide: Text.ElideNone
            }

            buttons: [
                Btn {
                    visible: ov.st === "running"
                    kind: "ghost"
                    label: "hide"
                    onClicked: Store.dialog = ""
                },
                Btn {
                    visible: ov.st === "done"
                    kind: "primary"
                    icon: "play"
                    label: "open"
                    focused: true
                    onClicked: {
                        Store.closeDialog();
                        Store.showToast("omarchy plugin toggle · opened " + (Installer.rec ? Installer.rec.name : ""));
                    }
                },
                Btn {
                    visible: ov.st === "failed"
                    kind: "ghost"
                    label: "close"
                    focused: true
                    onClicked: Store.closeDialog()
                }
            ]
        }

        // ---- remove --------------------------------------------------------------------
        Dialog {
            anchors.centerIn: parent
            visible: Store.dialog === "remove"
            glyph: "trash"
            title: "remove " + (ov.r.name || "") + "?"
            footNote: Installer.dev ? "fake runner (--dev)" : "runs omarchy-plugin-remove " + (ov.r.id || "") + " --yes"

            Txt {
                width: parent.width
                text: "Disables the plugin and deletes ~/.config/omarchy/plugins/" + (ov.r.id || "") + "."
                color: Theme.textSecondary
                wrapMode: Text.Wrap
                elide: Text.ElideNone
            }

            buttons: [
                Btn {
                    kind: "ghost"
                    label: "cancel"
                    key: "esc"
                    onClicked: Store.closeDialog()
                },
                Btn {
                    kind: "danger"
                    icon: "trash"
                    label: "remove"
                    key: "y"
                    focused: true
                    onClicked: ov.confirmAction()
                }
            ]
        }

        // ---- ranking explainer -----------------------------------------------------------
        Dialog {
            anchors.centerIn: parent
            visible: Store.dialog === "rank"
            width: 680
            glyph: "rank"
            title: "how ranking works" + (Store.dialogRec ? " · " + (ov.r.rank ? "#" + ov.r.rank + " " : "") + ov.r.name : "")

            Txt {
                width: parent.width
                textFormat: Text.StyledText
                text: "Rank = weighted sum of open factors (docs/RANKING.md), computed nightly by the public collector from GitHub and marketplace stats. Safety gates apply after the sum and only demote: <font color='" + Theme.red + "'><b>blocked</b></font> never appears on shelves, <font color='" + Theme.orange + "'><b>risky</b></font> ×0.6. Review status never moves a plugin (ADR-0030)."
                color: Theme.textSecondary
                wrapMode: Text.Wrap
                elide: Text.ElideNone
            }

            Table {
                width: parent.width
                head: Store.dialogRec ? ["factor", "weight", "source", ov.r.name || ""] : ["factor", "weight", "source"]
                widths: Store.dialogRec ? [170, 60, 210, parent.width - 440] : [190, 70, parent.width - 260]
                rows: Rank.explain(ov.r, Store.meta.factors, Date.now()).map(x => Store.dialogRec ? [x.label, String(x.weight), x.source, Number(x.value).toFixed(1) + "  " + x.detail] : [x.label, String(x.weight), x.source]).concat([Store.dialogRec ? ["safety gate", "", "×1 safe/caution/unreviewed · ×0.6 risky · blocked hidden", "×" + Rank.gateOf(ov.r.verdict) + " → " + (ov.r.rankScore === null || ov.r.rankScore === undefined ? "—" : Number(ov.r.rankScore).toFixed(1))] : ["safety gate", "", "×1 safe/caution/unreviewed · ×0.6 risky · blocked hidden"]])
            }

            Txt {
                width: parent.width
                text: "shelves: top = rank · trending = ★ velocity · new = listedAt · updated = repository push · safe picks = safe + rank. weights shown are placeholder values" + "."
                size: 11
                color: Theme.muted
                wrapMode: Text.Wrap
                elide: Text.ElideNone
            }

            buttons: [
                Btn {
                    kind: "ghost"
                    label: "close"
                    key: "esc"
                    focused: true
                    onClicked: Store.closeDialog()
                }
            ]
        }
    }

    // ---- toast -------------------------------------------------------------------------
    Rectangle {
        visible: Store.toast !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 10
        width: toastText.implicitWidth + 24
        height: 28
        color: Theme.bgDeep
        border.color: Theme.brand
        border.width: 1

        Txt {
            id: toastText

            anchors.centerIn: parent
            text: Store.toast
            size: 11
        }
    }
}
