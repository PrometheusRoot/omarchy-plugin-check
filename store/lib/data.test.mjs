import assert from "node:assert/strict";
import { test } from "node:test";
import { devDetail, devSnapshotText } from "../tools/devdata.mjs";
import * as D from "./data.mjs";

const snap = JSON.parse(devSnapshotText());

const tiny = {
  imageBase: "https://plugins.omarchy.org/",
  apiBase: "api",
  catalog: { generatedAt: "2026-09-30T00:00:00Z", plugins: 3 },
  providers: [{ id: "opc", name: "omarchy-plugin-check", tier: "core", verification: "sigstore", rows: 2 }],
  ranking: { version: "v", factors: [{ id: "stars", label: "log(stars)", weight: 20 }], gates: { safe: 1 } },
  shelves: { top: ["a", "blk", "b", "ghost"], trending: ["blk"], new: [], updated: [], safePicks: ["a"], byCategory: { Widgets: ["blk", "a"] } },
  categories: [{ name: "Widgets", count: 2 }],
  plugins: [
    { id: "a", name: "Alpha Widget", author: "x", desc: "d", cat: "Widgets", kind: "Bar widget", tags: ["t"], repo: "https://github.com/x/a", state: "listed", verif: "verified", listed: "2026-01-02T00:00:00Z", updated: null, img: { thumb: "assets/a.webp", full: "assets/a-big.webp" }, gallery: [], gh: { stars: 5, vel30: 1, lastCommit: "2026-09-01T00:00:00Z" }, mkt: null, rank: 1, score: 50, fac: [10], verdict: { combined: "safe", basis: "trusted", contested: false, commit: "c".repeat(40), providers: { opc: "safe" } }, report: "plugins/a.json" },
    { id: "blk", name: "Blocked", cat: "Widgets", tags: [], state: "listed", img: null, gh: null, mkt: null, rank: null, score: null, fac: [], verdict: { combined: "blocked", basis: "trusted", contested: false, providers: {} }, report: null },
    { id: "b", name: "b", cat: null, tags: [], state: "listed", img: { thumb: "https://cdn.example/b.png" }, gh: null, mkt: null, rank: 2, score: 1, fac: [], verdict: { combined: "unknown", basis: "none", contested: false, providers: {} }, report: null },
  ],
};

test("fromSnapshot maps the store.json draft onto the UI model", () => {
  const m = D.fromSnapshot(tiny);
  const a = m.plugins[m.byId.a];
  assert.equal(a.thumb, "https://plugins.omarchy.org/assets/a.webp");
  assert.equal(a.full, "https://plugins.omarchy.org/assets/a-big.webp");
  assert.equal(a.updated, "2026-09-01", "falls back to gh.lastCommit");
  assert.equal(a.listed, "2026-01-02");
  assert.equal(a.ini, "AW");
  assert.equal(a.views, null, "mkt null -> no engagement data");
  assert.equal(m.plugins[m.byId.b].verdict, "unreviewed", "unknown -> unreviewed");
  assert.equal(m.plugins[m.byId.b].cat, "Other");
  assert.equal(m.plugins[m.byId.b].thumb, "https://cdn.example/b.png", "absolute URLs kept");
  assert.equal(m.counts.safe, 1);
  assert.equal(m.counts.blocked, 1);
  assert.equal(m.counts.images, 2);
  assert.equal(m.meta.apiBase, "api");
  assert.equal(D.catCount(m, "Widgets"), 2);
  assert.equal(D.catCount(m, "Nope"), 0);
});

test("blocked never reaches shelves or the hero; unknown ids are dropped", () => {
  const m = D.fromSnapshot(tiny);
  const names = (ixs) => ixs.map((i) => m.plugins[i].id);
  assert.deepEqual(names(m.shelves.top), ["a", "b"]);
  assert.deepEqual(names(m.shelves.trending), []);
  assert.deepEqual(names(m.shelves.byCategory.Widgets), ["a"]);
  assert.deepEqual(names(m.heroes), ["a", "b"], "heroes need an image (full, else thumb)");
});

test("the full dev snapshot maps 4,523 plugins with 3 reviewed", () => {
  const m = D.fromSnapshot(snap);
  assert.equal(m.plugins.length, 4523);
  assert.equal(m.counts.unreviewed, 4520);
  assert.equal(m.counts.caution, 3);
  assert.ok(m.heroes.length > 0 && m.heroes.length <= D.HERO_COUNT);
  assert.ok(m.meta.dev);
  for (const p of m.plugins) {
    assert.ok(p.id && p.name !== undefined);
    assert.ok(["safe", "caution", "risky", "blocked", "unreviewed"].includes(p.verdict));
  }
});

test("fromDetail maps the aggregated view and our report", () => {
  const d = D.fromDetail(devDetail("omamail"), snap.providers);
  assert.equal(d.combined.verdict, "caution");
  assert.equal(d.providers.length, 2);
  assert.equal(d.providers[0].name, "omarchy-plugin-check");
  assert.equal(d.providers[0].signed, false, "unsigned-dev is not a signature");
  assert.ok(d.hasReport);
  assert.equal(d.risk, 13);
  assert.ok(d.findings.length > 0 && d.findings.length <= 12);
  assert.ok(d.findingCount >= d.findings.length);
  assert.equal(d.caps.processExec, "med");
  assert.ok(d.hosts.some((h) => h.host === "accounts.google.com"));
  assert.equal(d.weeks.length, 52);
  assert.ok(d.reviewedCommit.startsWith("3d0d673"));
  // findings come most severe first
  const order = ["critical", "high", "medium", "low", "info"];
  for (let i = 1; i < d.findings.length; i++) assert.ok(order.indexOf(d.findings[i - 1].sev) <= order.indexOf(d.findings[i].sev));
});

test("fromDetail without our report still lists providers", () => {
  const d = D.fromDetail({ combined: { verdict: "unknown" }, providers: [{ provider: "marketplace", tier: "unsigned", verification: "unsigned", verdict: "unknown" }] }, []);
  assert.equal(d.hasReport, false);
  assert.equal(d.combined.verdict, "unreviewed");
  assert.equal(d.providers[0].name, "marketplace");
});

test("parseInstalled reads `id sha` lines", () => {
  const m = D.parseInstalled("omamail 3d0d673715cb0fb4f49cb718c2a2dbc002ee8763\nno-git \n../evil abc\n\n");
  assert.equal(m.omamail.sha, "3d0d673715cb0fb4f49cb718c2a2dbc002ee8763");
  assert.equal(m["no-git"].sha, "");
  assert.equal(m["../evil"], undefined);
});
