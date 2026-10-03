import assert from "node:assert/strict";
import { test } from "node:test";
import * as FR from "./firstrun.mjs";

const run = (s, ...evs) => evs.reduce((a, e) => FR.reduce(a, e), s);

test("a verified bundle goes straight to ready; --dev never verifies", () => {
  assert.equal(run(FR.start({}), { type: "verified", code: 0 }).state, "ready");
  assert.equal(FR.start({ dev: true }).state, "ready");
});

test("first run: no bundle -> update with the bundled checker -> verify again -> ready", () => {
  let s = run(FR.start({}), { type: "checker", found: true }, { type: "verified", code: 3, err: "store-verify: no bundle in /x" });
  assert.equal(s.state, "updating");
  assert.equal(FR.view(s).title, "getting the plugin catalog…");
  assert.equal(FR.view(s).busy, true);
  s = FR.reduce(s, { type: "updated", code: 0 });
  assert.deepEqual([s.state, s.updated], ["verifying", true]);
  assert.equal(FR.view(s).title, "verifying the new snapshot…");
  assert.equal(FR.reduce(s, { type: "verified", code: 0 }).state, "ready");
});

test("the checker probe may answer after the verifier: wait, then update", () => {
  let s = run(FR.start({}), { type: "verified", code: 3 });
  assert.equal(s.state, "waiting");
  assert.equal(FR.view(s).busy, true);
  s = FR.reduce(s, { type: "checker", found: true });
  assert.equal(s.state, "updating");
});

test("an expired or damaged bundle is refreshed once, then reported", () => {
  let s = run(FR.start({}), { type: "checker", found: true }, { type: "verified", code: 1, err: "store-verify: expired at 2026-01-01T00:00:00Z" });
  assert.equal(s.state, "updating");
  assert.equal(FR.view(s).title, "refreshing the plugin catalog…");
  s = run(s, { type: "updated", code: 0 }, { type: "verified", code: 1, err: "store-verify: a file's sha256 differs from the manifest" });
  assert.equal(s.state, "failed");
  const v = FR.view(s);
  assert.equal(v.title, "the snapshot did not verify");
  assert.match(v.detail, /sha256 differs/);
  assert.equal(v.retry, true);
});

test("an update failure is friendly, one line, and retry runs the update again", () => {
  const err = "  ! something\nomarchy-plugin-check: could not fetch https://example.invalid/store-manifest.json\n";
  let s = run(FR.start({}), { type: "checker", found: true }, { type: "verified", code: 3 }, { type: "updated", code: 4, err });
  assert.equal(s.state, "failed");
  const v = FR.view(s);
  assert.equal(v.title, "can't reach the snapshot server");
  assert.equal(v.detail, "check your connection, then retry · could not fetch https://example.invalid/store-manifest.json");
  assert.ok(!/\n/.test(v.detail));
  s = FR.reduce(s, { type: "retry" });
  assert.deepEqual([s.state, s.updated, s.err], ["updating", false, ""]);
});

test("no checker: failed with a reinstall hint; retry only verifies again", () => {
  let s = run(FR.start({}), { type: "checker", found: false }, { type: "verified", code: 3 });
  assert.equal(s.state, "failed");
  assert.equal(FR.view(s).title, "the checker is missing");
  assert.equal(FR.reduce(s, { type: "retry" }).state, "verifying");
});

test("OPC_STORE_BUNDLE (autoUpdate false) never updates", () => {
  const s = run(FR.start({ autoUpdate: false }), { type: "checker", found: true }, { type: "verified", code: 3 });
  assert.equal(s.state, "failed");
});

test("events out of order are ignored", () => {
  const s = FR.start({});
  assert.equal(FR.reduce(s, { type: "updated", code: 0 }), s);
  assert.equal(FR.reduce(s, { type: "retry" }), s);
  assert.equal(FR.reduce(s, null), s);
  const ready = FR.reduce(s, { type: "verified", code: 0 });
  assert.equal(FR.reduce(ready, { type: "verified", code: 1 }), ready);
  assert.deepEqual(FR.view(ready), { title: "", detail: "", busy: false, retry: false });
});

test("reason: last line, prefixes and the keep note stripped, capped", () => {
  assert.equal(FR.reason("omarchy-plugin-check: snapshot rejected: bad signature (store-manifest.json) (kept the last accepted one)"), "bad signature (store-manifest.json)");
  assert.equal(FR.reason("Error: x\n    at foo (bar.js:1)\n"), "Error: x");
  assert.equal(FR.reason("x".repeat(400)).length, 158);
  assert.equal(FR.reason(""), "");
  assert.equal(FR.view({ state: "failed", phase: "update", err: "" }).detail, "the checker exited without saying why");
});

test("update argv: absolute validated path only", () => {
  assert.deepEqual(FR.updateArgv("/home/u/p/bin/omarchy-plugin-check"), ["/home/u/p/bin/omarchy-plugin-check", "update"]);
  assert.equal(FR.updateArgv("omarchy-plugin-check"), null);
  assert.equal(FR.updateArgv("/home/my dir/x"), null);
  assert.equal(FR.updateArgv(""), null);
});
