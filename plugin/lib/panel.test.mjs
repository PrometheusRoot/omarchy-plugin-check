import { test } from "node:test";
import assert from "node:assert/strict";
import * as P from "./panel.mjs";

const sha = (c) => c.repeat(40);
const doc = {
  schemaVersion: 1,
  kind: "omarchy-plugin-check/status",
  generatedAt: "2026-10-02T12:00:00Z",
  snapshot: {
    ok: true, version: 1790960463, generatedAt: "2026-10-02T10:00:00Z", dev: true,
    providers: [{ id: "opc", tier: "core" }, { id: "marketplace", tier: "unsigned" }]
  },
  worst: "blocked",
  plugins: [
    { id: "omamail", name: "Omamail", head: sha("b"), state: "safe", combined: "safe", reviewed: { commit: sha("9") }, commitMatch: false, treeMatch: true, url: "https://plugins.omarchy.org/plugin.html?id=omamail" },
    { id: "io.github.letsfg.flights", name: "LetsFG Flights", head: sha("8"), state: "stale", combined: "caution", reviewed: { commit: sha("3") }, commitMatch: false, treeMatch: false },
    { id: "io.github.example-fixtures.blocked-widget", name: "Weather Pro", head: sha("a"), state: "blocked", combined: "blocked", reviewed: { commit: sha("a") }, commitMatch: true, treeMatch: true },
    { id: "dev.local.my-clock", name: "My Clock", head: sha("0"), state: "unlisted", combined: null, reviewed: { commit: null }, commitMatch: null, treeMatch: null, note: "" },
    { id: "omarchy-netspeed-legacy", name: "Netspeed", head: null, state: "retired", reviewed: { commit: null }, commitMatch: null, treeMatch: null }
  ]
};

test("parseStatus accepts only our document", () => {
  assert.equal(P.parseStatus(JSON.stringify(doc)).doc.plugins.length, 5);
  assert.equal(P.parseStatus("").error, "no status yet");
  assert.equal(P.parseStatus("{").error, "unreadable status.json");
  assert.equal(P.parseStatus('{"kind":"x","plugins":[]}').error, "not a status document");
});

test("worst state and its count; unknown states count as unreviewed", () => {
  assert.deepEqual(P.worst(doc), { state: "blocked", count: 1 });
  assert.deepEqual(P.worst({ plugins: [] }), { state: null, count: 0 });
  assert.deepEqual(P.worst(null), { state: null, count: 0 });
  assert.deepEqual(P.worst({ plugins: [{ state: "safe" }, { state: "caution" }, { state: "caution" }] }), { state: "caution", count: 2 });
  assert.deepEqual(P.worst({ plugins: [{ state: "weird" }, { state: "safe" }] }), { state: "unreviewed", count: 1 });
  // the full order, worst last
  for (let i = 1; i < P.ORDER.length; i++)
    assert.equal(P.worst({ plugins: P.ORDER.slice(0, i + 1).map((s) => ({ state: s })) }).state, P.ORDER[i]);
});

test("shield: count hidden when safe or empty; tint follows the state", () => {
  assert.equal(P.shieldLabel({ state: "safe", count: 3 }), P.ICON.shield);
  assert.equal(P.shieldLabel({ state: null, count: 0 }), P.ICON.shield);
  assert.equal(P.shieldLabel({ state: "risky", count: 2 }), P.ICON.shield + " 2");
  assert.equal(P.COLOR.blocked, "red");
  assert.equal(P.COLOR.stale, "blue");
  assert.match(P.shieldTip({ state: "blocked", count: 1 }, doc), /^omarchy-store · worst: blocked \(1\)\nclick: store · right click: verdicts/);
  assert.match(P.shieldTip({ state: null, count: 0 }, null), /^omarchy-store · no third-party plugins\n/);
  assert.match(P.shieldTip({ state: "safe", count: 1 }, { snapshot: { ok: false } }), /no verified snapshot/);
});

test("rows: worst first, stale chip names the reviewed outcome, remove only for blocked/retired", () => {
  const r = P.rows(doc);
  assert.deepEqual(r.map((x) => x.state), ["blocked", "retired", "stale", "unlisted", "safe"]);
  const stale = r.find((x) => x.state === "stale");
  assert.equal(stale.chip, "caution@3333333");
  assert.equal(stale.chipColor, "yellow");
  assert.equal(stale.commitEq + stale.treeEq, "≠≠");
  const safe = r.find((x) => x.id === "omamail");
  assert.equal(safe.sub, "omamail · bbbbbbb");
  assert.equal(safe.commitEq + safe.treeEq, "≠=");
  assert.equal(safe.url, "https://plugins.omarchy.org/plugin.html?id=omamail");
  assert.deepEqual(r.filter((x) => x.removable).map((x) => x.state), ["blocked", "retired"]);
  assert.equal(r.find((x) => x.state === "unlisted").hasMatch, false);
  assert.equal(r.find((x) => x.state === "blocked").treeEq, "=");
  assert.equal(r.find((x) => x.state === "unlisted").treeEq, "—");
  assert.equal(r.find((x) => x.state === "retired").sub, "omarchy-netspeed-legacy · —");
});

test("snapshot badge: verified age or the reason", () => {
  const now = Date.parse("2026-10-02T12:00:00Z") / 1000;
  const b = P.snapshotBadge(doc, now);
  assert.equal(b.text, "snapshot ✓ · 2h");
  assert.match(b.tip, /dev key/);
  assert.match(b.tip, /providers opc core, marketplace unsigned/);
  assert.deepEqual(P.snapshotBadge({ snapshot: { ok: false, error: "expired at X" } }, now), { ok: false, text: "snapshot ✗", tip: "expired at X" });
  assert.equal(P.age(59), "59s");
  assert.equal(P.age(3600 * 49), "2d");
  assert.equal(P.age(-1), "?");
});

test("argv: ids and paths are validated before they reach a shell", () => {
  const bin = P.cliPath("file:///home/u/.config/omarchy/plugins/io.github.prometheusroot.omarchy-store/");
  assert.equal(bin, "/home/u/.config/omarchy/plugins/io.github.prometheusroot.omarchy-store/bin/omarchy-plugin-check");
  assert.deepEqual(P.rescanArgv(bin), [bin, "status", "--json"]);
  assert.deepEqual(P.cardArgv(bin, "omamail"), ["omarchy-launch-floating-terminal-with-presentation", bin + " omamail"]);
  assert.equal(P.cardArgv(bin, "x; rm -rf ~"), null);
  assert.equal(P.cardArgv(bin, "a..b"), null);
  assert.equal(P.cardArgv("/home/my dir/bin/x", "omamail"), null);
  assert.equal(P.cliPath("file:///home/my dir/p"), "");
  assert.equal(P.rescanArgv(""), null);
  const dir = "file:///home/u/.config/omarchy/plugins/io.github.prometheusroot.omarchy-store/";
  assert.deepEqual(P.storeArgv(dir), ["/home/u/.config/omarchy/plugins/io.github.prometheusroot.omarchy-store/store/bin/omarchy-store"]);
  assert.equal(P.storeArgv("file:///home/my dir/p"), null);
  assert.equal(P.storeArgv("file:///home/u/$(id)"), null);
  assert.equal(P.PLUGIN_ID, "io.github.prometheusroot.omarchy-store");
  assert.deepEqual(P.removeArgv("omamail"), ["omarchy-launch-floating-terminal-with-presentation", "omarchy plugin remove omamail"]);
  assert.equal(P.removeArgv("$(id)"), null);
  assert.deepEqual(P.openArgv(P.SITE), ["xdg-open", P.SITE]);
  assert.equal(P.openArgv("javascript:alert(1)"), null);
  assert.equal(P.openArgv("https://x.org/a b"), null);
});

test("palette from colors.toml with fallbacks", () => {
  const pal = P.palette('foreground = "#cdd6f4"\nbackground = "#1e1e2e"\ncolor2 = "#a6e3a1"\nred = "#f38ba8" # comment\n');
  assert.equal(pal.fg, "#cdd6f4");
  assert.equal(pal.green, "#a6e3a1");
  assert.equal(pal.red, "#f38ba8");
  assert.equal(pal.blue, "#7aa2f7");
  assert.equal(P.tint(pal, "green"), "#a6e3a1");
  assert.equal(P.tint(pal, "nope"), "#cdd6f4");
  assert.equal(P.palette("").orange, "#ff9e64");
});
