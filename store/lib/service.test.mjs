import assert from "node:assert/strict";
import { test } from "node:test";
import { devHomeText, devSearchText } from "../tools/devdata.mjs";
import * as S from "./service.mjs";

// The worker protocol, driven exactly as ui/worker.mjs does (messages in, replies out).
const home = JSON.parse(devHomeText());
const svc = S.createService();
const loaded = S.handle(svc, { type: "load", text: devSearchText(), imageBase: home.imageBase, byCategory: home.shelves.byCategory });

test("load parses the search columns (the home slice never comes here)", () => {
  assert.equal(loaded.type, "loaded");
  assert.equal(loaded.total, home.total);
  assert.ok(loaded.ms.parse >= 0 && loaded.ms.map >= 0);
});

test("index then search: rows, count, words; stale seqs are the UI's job", () => {
  assert.equal(S.handle(svc, { type: "index" }).type, "indexed");
  let w = { next: 0 };
  let chunks = 0;
  while (w.next !== -1) {
    w = S.handle(svc, { type: "warm", from: w.next, count: 8 });
    chunks++;
  }
  assert.equal(chunks, 5);
  assert.equal(Object.keys(svc.idx.cache).length, 36);
  const r = S.handle(svc, { type: "search", seq: 7, q: "weather", f: {}, sort: "rank", limit: 10 });
  assert.equal(r.type, "results");
  assert.equal(r.seq, 7);
  assert.ok(r.count > 10);
  assert.equal(r.rows.length, 10);
  assert.deepEqual(r.words, ["weather"]);
  assert.match(r.rows[0].name.toLowerCase(), /weather/);
  const page = S.handle(svc, { type: "page", seq: 7, offset: 10, limit: 10 });
  assert.equal(page.rows.length, 10);
  assert.notEqual(page.rows[0].id, r.rows[0].id);
});

test("installed filter uses the installed map sent with the query", () => {
  const r = S.handle(svc, { type: "search", seq: 8, q: "", f: { inst: true, instVersion: 1 }, sort: "rank", installed: { omamail: true } });
  assert.deepEqual(r.rows.map((x) => x.id), ["omamail"]);
});

test("records, browse, similar, bench", () => {
  const rec = S.handle(svc, { type: "records", tag: "installed", ids: ["omamail", "nope"] });
  assert.deepEqual(rec.rows.map((x) => x.id), ["omamail"]);
  const b = S.handle(svc, { type: "browse", cat: "Productivity", kind: "all", limit: 30 });
  assert.equal(b.rows.length, 30);
  assert.ok(b.rows.every((x) => x.cat === "Productivity" && x.verdict !== "blocked"));
  for (let i = 1; i < b.rows.length; i++) assert.ok((b.rows[i - 1].rank || 1e9) <= (b.rows[i].rank || 1e9));
  const k = S.handle(svc, { type: "browse", cat: "Widgets", kind: "Overlay", limit: 30 });
  assert.ok(k.rows.every((x) => x.kind === "Overlay"));
  const sim = S.handle(svc, { type: "similar", id: "omamail" });
  assert.ok(sim.rows.length > 0 && sim.rows.length <= 4 && sim.rows.every((x) => x.id !== "omamail"));
  assert.deepEqual(S.handle(svc, { type: "similar", id: "nope" }).rows, []);
  const bench = S.handle(svc, { type: "bench", phrases: ["omarchy"], reps: 1 });
  assert.equal(bench.n, 7);
  assert.equal(S.handle(svc, { type: "nope" }).type, "error");
});
