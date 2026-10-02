pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/install.mjs" as Inst
import "../lib/data.mjs" as Data

// Install / update / remove through `omarchy-plugin-check --add --pin <repo>` (argv, never
// a shell string; lib/install.mjs). The checker CLI may be absent: install is then
// disabled with "checker not installed". `--dev` swaps in a fake runner that replays the
// state machine, and a fixed installed list, so every dialog and state can be exercised.
Singleton {
    id: root

    readonly property bool dev: Quickshell.env("OPC_STORE_DEV") === "1"
    property bool checker: false
    property bool probed: false
    readonly property bool canInstall: checker || dev
    readonly property string why: canInstall ? "" : "checker not installed"

    // Install flow state (lib/install.mjs reduce); `rec` is the plugin record.
    property var flow: Inst.start(null, {})
    property var rec: null
    readonly property string state: flow ? flow.state : "idle"

    // id -> {sha, state?, reviewed?, upstream?}
    property var installed: ({})
    property int installedVersion: 0
    signal finished(var rec, bool ok)
    signal removed(string id)

    // repin: update / roll back an installed plugin to the reviewed commit.
    function begin(r, repin) {
        rec = r;
        flow = Inst.start(r, {
            checker: checker,
            dev: dev,
            installed: !repin && !!installed[r.id]
        });
        if (flow.state === "running")
            run();
    }

    function confirm() {
        flow = Inst.reduce(flow, {
            type: "confirm"
        });
        if (flow.state === "running")
            run();
    }

    function close() {
        if (flow.state === "running")
            return; // keeps running; the dialog can come back with `i`
        flow = Inst.reduce(flow, {
            type: "close"
        });
    }

    function hide() {
        flow = Inst.reduce(flow, {
            type: "close"
        });
    }

    function run() {
        if (dev) {
            fake.script = Inst.fakeScript(rec, 420);
            fake.at = 0;
            fake.restart();
            return;
        }
        const argv = Inst.command(rec);
        if (!argv) {
            flow = Inst.reduce(flow, {
                type: "exit",
                code: 2
            });
            return;
        }
        runner.command = argv;
        runner.running = true;
    }

    function apply(ev) {
        flow = Inst.reduce(flow, ev);
        if (ev.type === "exit") {
            if (flow.state === "done") {
                const map = Object.assign({}, installed);
                map[rec.id] = {
                    sha: rec.commit ? String(rec.commit).slice(0, 7) : "",
                    state: "ok"
                };
                installed = map;
                installedVersion++;
                if (!dev)
                    probe.running = true;
            }
            finished(rec, flow.state === "done");
        }
    }

    // Remove (no checker needed: omarchy's own CLI).
    function remove(r) {
        const map = Object.assign({}, installed);
        delete map[r.id];
        if (!dev) {
            const argv = Inst.removeCommand(r);
            if (!argv)
                return;
            remover.command = argv;
            remover.running = true;
        }
        installed = map;
        installedVersion++;
        removed(r.id);
    }

    function stateOf(r) {
        const e = installed[r.id];
        if (!e)
            return "";
        return e.state || Inst.installState(e.sha, r);
    }

    Timer {
        id: fake

        property var script: []
        property int at: 0

        interval: 420
        repeat: true
        onTriggered: {
            if (at >= script.length) {
                stop();
                return;
            }
            root.apply(script[at].ev);
            at++;
        }
    }

    Process {
        id: runner

        stdout: SplitParser {
            onRead: line => root.apply({
                    type: "line",
                    text: line
                })
        }
        stderr: SplitParser {
            onRead: line => root.apply({
                    type: "line",
                    text: line
                })
        }
        onExited: code => root.apply({
                type: "exit",
                code: code
            })
    }

    Process {
        id: remover
    }

    Process {
        running: true
        command: ["sh", "-c", "command -v omarchy-plugin-check"]
        onExited: code => {
            root.checker = code === 0;
            root.probed = true;
        }
    }

    // Installed plugins: directory name = plugin id, HEAD from git.
    Process {
        id: probe

        running: !root.dev
        command: ["sh", "-c", "for d in \"$HOME\"/.config/omarchy/plugins/*/; do [ -d \"$d\" ] || continue; printf '%s %s\\n' \"$(basename \"$d\")\" \"$(git -C \"$d\" rev-parse HEAD 2>/dev/null)\"; done"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.installed = Data.parseInstalled(text);
                root.installedVersion++;
            }
        }
    }

    // --dev: a fixed installed list covering every row state of the mockup that the dev
    // snapshot can express (update, stale, ok, unreviewed).
    Component.onCompleted: {
        if (!dev)
            return;
        installed = {
            "omamail": {
                sha: "b7f0a91",
                state: "update",
                upstream: "c31e0d4"
            },
            "io.github.letsfg.flights": {
                sha: "8b21e07",
                state: "stale"
            },
            "akitaonrails.ai-usagebar": {
                sha: "b1766cb",
                state: "ok"
            },
            "tornikegomareli.spaces": {
                sha: "1d4e77a"
            },
            "slcode777.omagotchi": {
                sha: "4a9c2f0"
            }
        };
        installedVersion++;
    }
}
