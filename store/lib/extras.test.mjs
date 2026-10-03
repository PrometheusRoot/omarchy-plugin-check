import assert from "node:assert/strict";
import { test } from "node:test";
import * as X from "./extras.mjs";

const BIN = "/home/u/.config/omarchy/plugins/io.github.prometheusroot.omarchy-store/bin/omarchy-plugin-check";
const addPlan = JSON.stringify({
  mode: "add", pending: true, keybind: "SUPER + SHIFT + ALT + S",
  changes: [
    { what: "link", action: "create", path: "/h/.local/bin/omarchy-plugin-check", text: "link ~/.local/bin/omarchy-plugin-check → …" },
    { what: "link", action: "keep", path: "/h/.local/bin/omarchy-store", text: "~/.local/bin/omarchy-store already links to …" },
    { what: "menu", action: "edit", path: "/h/m", text: "menu …: add Install › Plugin Store (backup kept)" },
    { what: "keybind", action: "edit", path: "/h/b", text: "keybind SUPER + SHIFT + ALT + S → omarchy-store in ~/.config/hypr/bindings.lua (backup kept)" }
  ]
});
const donePlan = JSON.stringify({
  mode: "add", pending: false, keybind: "SUPER + SHIFT + ALT + S",
  changes: ["link", "link", "menu", "keybind"].map((what) => ({ what, action: "keep", text: what }))
});

test("argv: the bundled checker by absolute path; --yes only for the apply", () => {
  assert.deepEqual(X.planArgv(BIN, false), [BIN, "setup", "--plan", "--json"]);
  assert.deepEqual(X.planArgv(BIN, true), [BIN, "setup", "--uninstall", "--plan", "--json"]);
  assert.deepEqual(X.applyArgv(BIN, false), [BIN, "setup", "--yes", "--json"]);
  assert.deepEqual(X.applyArgv(BIN, true), [BIN, "setup", "--uninstall", "--yes", "--json"]);
  assert.equal(X.planArgv("omarchy-plugin-check", false), null);
  assert.equal(X.applyArgv("/x y/z", true), null);
});

test("the dialog lists exactly the plan's changes, with a sign per action", () => {
  const p = X.parsePlan(addPlan);
  assert.equal(p.ok, true);
  assert.equal(p.pending, true);
  assert.deepEqual(p.changes.map((c) => c.sign + " " + c.what), ["+ link", "= link", "+ menu", "+ keybind"]);
  assert.match(p.changes[3].text, /SUPER \+ SHIFT \+ ALT \+ S/);
  assert.equal(X.parsePlan("garbage").ok, false);
  assert.equal(X.parsePlan('{"changes": 1}').ok, false);
  // the CLI may print a progress line before the JSON
  assert.equal(X.parsePlan("  ✓ x\n" + donePlan).ok, true);
});

test("summary: what is already in place", () => {
  assert.deepEqual(X.summary(X.parsePlan(addPlan)), { known: true, menu: false, keybind: "", command: false, all: false });
  assert.deepEqual(X.summary(X.parsePlan(donePlan)), { known: true, menu: true, keybind: "SUPER + SHIFT + ALT + S", command: true, all: true });
  assert.equal(X.summary(null).known, false);
});

test("flow: plan -> confirm -> running -> done; nothing to do; failures", () => {
  let s = X.start(false);
  assert.equal(s.state, "planning");
  s = X.reduce(s, { type: "plan", text: addPlan });
  assert.equal(s.state, "confirm");
  assert.equal(X.reduce(s, { type: "exit", code: 0 }), s); // not running yet
  s = X.reduce(s, { type: "confirm" });
  assert.equal(s.state, "running");
  assert.equal(X.reduce(s, { type: "close" }), s); // a running setup is never abandoned
  s = X.reduce(s, { type: "line", text: "  ✓ linked ~/.local/bin/omarchy-store" });
  assert.deepEqual(s.log, ["  ✓ linked ~/.local/bin/omarchy-store"]);
  assert.equal(X.reduce(s, { type: "exit", code: 0 }).state, "done");
  assert.equal(X.reduce(s, { type: "exit", code: 1 }).state, "failed");
  assert.equal(X.reduce(X.start(true), { type: "plan", text: donePlan }).state, "nothing");
  assert.equal(X.reduce(X.start(false), { type: "plan", text: "" }).state, "failed");
  assert.equal(X.reduce(X.reduce(X.start(true), { type: "plan", text: addPlan }), { type: "close" }).state, "idle");
  assert.equal(X.start(true).undo, true);
  assert.equal(X.reduce(null, { type: "close" }), null);
});
