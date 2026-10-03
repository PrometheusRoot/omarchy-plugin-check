pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/extras.mjs" as X

// Opt-in extras (status tab, ADR-0042): Omarchy menu entry, store keybind, terminal commands,
// through the bundled checker's `setup` (lib/extras.mjs). The plan shown in the confirm dialog
// comes from `setup --plan --json`; the apply recomputes it from the same facts. Undo runs
// `setup --uninstall`. Nothing changes before the user confirms.
Singleton {
    id: root

    readonly property bool dev: Quickshell.env("OPC_STORE_DEV") === "1"
    property var flow: X.idle()
    readonly property string state: flow.state
    // What is in place now (the add plan, refreshed on the status tab and after each apply).
    property var current: null
    readonly property var summary: X.summary(current)
    readonly property bool available: Installer.checker && !dev

    // Re-read what is in place (status tab open, after apply).
    function refresh() {
        const argv = X.planArgv(Installer.bin, false);
        if (!argv || dev || probe.running)
            return;
        probe.command = argv;
        probe.running = true;
    }

    // Plan `setup` (undo = `setup --uninstall`) and open the confirm dialog with it.
    function open(undo) {
        const argv = X.planArgv(Installer.bin, undo);
        if (!argv || planner.running || runner.running)
            return;
        flow = X.start(undo);
        Store.dialog = "extras";
        planner.command = argv;
        planner.running = true;
    }

    function confirm() {
        const argv = X.applyArgv(Installer.bin, flow.undo);
        if (!argv || flow.state !== "confirm")
            return;
        flow = X.reduce(flow, {
            type: "confirm"
        });
        runner.command = argv;
        runner.running = true;
    }

    function close() {
        flow = X.reduce(flow, {
            type: "close"
        });
    }

    Connections {
        target: Installer

        function onProbedChanged() {
            root.refresh();
        }
    }

    Process {
        id: probe

        stdout: StdioCollector {
            id: probeOut
        }
        onExited: code => root.current = code === 0 ? X.parsePlan(probeOut.text) : null
    }

    Process {
        id: planner

        stdout: StdioCollector {
            id: planOut
        }
        onExited: root.flow = X.reduce(root.flow, {
            type: "plan",
            text: planOut.text
        })
    }

    Process {
        id: runner

        stdout: StdioCollector {}
        stderr: SplitParser {
            onRead: line => root.flow = X.reduce(root.flow, {
                    type: "line",
                    text: line
                })
        }
        onExited: code => {
            root.flow = X.reduce(root.flow, {
                type: "exit",
                code: code
            });
            root.refresh();
        }
    }
}
