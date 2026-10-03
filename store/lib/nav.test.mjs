import assert from "node:assert/strict";
import { test } from "node:test";
import * as N from "./nav.mjs";

const act = (key, ctx = {}) => N.keyAction(key, { tab: "search", cursor: true, ...ctx });

// The approved mockup's key map (status tab "keys" box + keydown handler).
test("global keys", () => {
  assert.deepEqual(act("/"), { action: "focusSearch" });
  for (const [k, tab] of [["1", "home"], ["2", "search"], ["3", "browse"], ["4", "installed"], ["5", "status"]])
    assert.deepEqual(act(k), { action: "tab", arg: tab });
  assert.deepEqual(act("j"), { action: "move", arg: "down" });
  assert.deepEqual(act("Down"), { action: "move", arg: "down" });
  assert.deepEqual(act("k"), { action: "move", arg: "up" });
  assert.deepEqual(act("Up"), { action: "move", arg: "up" });
  assert.deepEqual(act("l"), { action: "move", arg: "right" });
  assert.deepEqual(act("h"), { action: "move", arg: "left" });
  assert.deepEqual(act("Enter"), { action: "open" });
  assert.deepEqual(act("Escape"), { action: "back" });
  assert.deepEqual(act("i"), { action: "install" });
  assert.deepEqual(act("?"), { action: "rank" });
  assert.deepEqual(act("6"), { action: "none" });
});

test("h / l slide the hero on home when nothing is focused; arrows still move", () => {
  assert.deepEqual(act("l", { tab: "home", cursor: false }), { action: "hero", arg: 1 });
  assert.deepEqual(act("h", { tab: "home", cursor: false }), { action: "hero", arg: -1 });
  assert.deepEqual(act("Right", { tab: "home", cursor: false }), { action: "move", arg: "right" });
  assert.deepEqual(act("l", { tab: "home", cursor: true }), { action: "move", arg: "right" });
});

test("t cycles themes in dev builds only", () => {
  assert.deepEqual(act("t", { dev: true }), { action: "theme" });
  assert.deepEqual(act("t", { dev: false }), { action: "none" });
});

test("detail sections: o s x d a", () => {
  for (const [k, s] of [["o", "overview"], ["s", "security"], ["x", "tech"], ["d", "deps"], ["a", "activity"]])
    assert.deepEqual(act(k, { tab: "detail" }), { action: "section", arg: s });
  assert.deepEqual(act("s", { tab: "search" }), { action: "none" });
});

test("in the search field only esc, down and enter are ours", () => {
  assert.deepEqual(act("Down", { inInput: true }), { action: "leaveInput" });
  assert.deepEqual(act("Enter", { inInput: true }), { action: "leaveInput" });
  assert.deepEqual(act("Escape", { inInput: true }), { action: "back" });
  assert.deepEqual(act("j", { inInput: true }), { action: "type" });
  assert.deepEqual(act("1", { inInput: true }), { action: "type" });
});

test("dialogs: y confirms install / remove, enter is the default button, esc closes", () => {
  assert.deepEqual(act("y", { dialog: "confirm" }), { action: "confirm" });
  assert.deepEqual(act("y", { dialog: "remove" }), { action: "confirm" });
  assert.deepEqual(act("y", { dialog: "rank" }), { action: "none" });
  assert.deepEqual(act("Enter", { dialog: "refused" }), { action: "dialogDefault" });
  assert.deepEqual(act("Escape", { dialog: "confirm" }), { action: "back" });
  assert.deepEqual(act("j", { dialog: "confirm" }), { action: "none" });
});

test("modifier chords are left alone", () => {
  assert.deepEqual(act("j", { mods: true }), { action: "none" });
});

test("keyName maps Qt key codes", () => {
  assert.equal(N.keyName(N.QT.Escape, ""), "Escape");
  assert.equal(N.keyName(N.QT.Return, "\r"), "Enter");
  assert.equal(N.keyName(N.QT.Enter, ""), "Enter");
  assert.equal(N.keyName(N.QT.Down, ""), "Down");
  assert.equal(N.keyName(N.QT.PageDown, ""), "PageDown");
  assert.equal(N.keyName(0x4a, "j"), "j");
  assert.deepEqual(act("PageDown"), { action: "page", arg: 1 });
});

test("grid cursor movement", () => {
  const rows = [3, 0, 5, 2];
  assert.equal(N.move(rows, null, "up", true), null, "up from the hero stays on the hero");
  assert.deepEqual(N.move(rows, null, "down", true), { r: 0, c: 0 });
  assert.deepEqual(N.move(rows, { r: 0, c: 2 }, "down", true), { r: 2, c: 2 }, "skips empty rows, keeps column");
  assert.deepEqual(N.move(rows, { r: 2, c: 4 }, "down", true), { r: 3, c: 1 }, "clamps column");
  assert.deepEqual(N.move(rows, { r: 3, c: 1 }, "down", true), { r: 3, c: 1 }, "stays at the end");
  assert.equal(N.move(rows, { r: 0, c: 1 }, "up", true), null, "up from the first row returns to the hero");
  assert.deepEqual(N.move(rows, { r: 0, c: 1 }, "up", false), { r: 0, c: 1 });
  assert.deepEqual(N.move(rows, { r: 0, c: 0 }, "left", true), { r: 0, c: 0 });
  assert.deepEqual(N.move(rows, { r: 0, c: 2 }, "right", true), { r: 0, c: 2 });
  assert.equal(N.move([0, 0], null, "down", true), null);
  assert.deepEqual(N.gridRows(14, 6), [6, 6, 2]);
  assert.deepEqual(N.gridRows(0, 6), []);
});

test("status tab: e opens the extras dialog (ADR-0042); elsewhere e does nothing", () => {
  assert.deepEqual(N.keyAction("e", { tab: "status" }), { action: "extras" });
  assert.deepEqual(N.keyAction("e", { tab: "home" }), { action: "none" });
  assert.deepEqual(N.keyAction("y", { tab: "status", dialog: "confirm" }), { action: "confirm" });
  assert.deepEqual(N.keyAction("y", { tab: "status", dialog: "extras" }), { action: "none" });
});
