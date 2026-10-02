import assert from "node:assert/strict";
import { test } from "node:test";
import { devDetail, devHomeText, devSearchText } from "../tools/devdata.mjs";
import * as D from "./data.mjs";

const homeDoc = JSON.parse(devHomeText());
const searchDoc = JSON.parse(devSearchText());

const row = (id, extra = {}) => ({ id, name: id, cat: "Widgets", verdict: { combined: "unknown", basis: "none", providers: {} }, ...extra });
const tiny = {
  version: 9,
  imageBase: "https://plugins.omarchy.org/",
  apiBase: "api",
  catalog: { generatedAt: "2026-09-30T00:00:00Z", plugins: 3 },
  providers: [{ id: "opc", name: "omarchy-plugin-check", tier: "core", verification: "sigstore", rows: 2 }],
  ranking: { version: "v", factors: [{ id: "stars", label: "log(stars)", weight: 20 }], gates: { safe: 1 } },
  categories: [{ name: "Widgets", count: 2 }],
  counts: { safe: 1, caution: 0, risky: 0, blocked: 1, unknown: 1, images: 2 },
  total: 3,
  shelves: { top: ["a", "blk", "b", "ghost"], trending: ["blk"], new: [], updated: [], safePicks: ["a"], byCategory: { Widgets: ["blk", "a"] } },
  plugins: [
    row("a", { name: "Alpha Widget", author: "x", listed: "2026-01-02T00:00:00Z", img: { thumb: "assets/a.webp", full: "assets/a-big.webp" }, gh: { stars: 5, vel30: 1, lastCommit: "2026-09-01T00:00:00Z" }, rank: 1, verdict: { combined: "safe", basis: "trusted", commit: "c".repeat(40), providers: { opc: "safe" }, criteria: { checked: ["no-exec"], failed: [] }, risk: 4 }, report: true }),
    row("blk", { verdict: { combined: "blocked", basis: "trusted", providers: {} } }),
    row("b", { cat: undefined, img: { thumb: "https://cdn.example/b.png" }, rank: 2 }),
  ],
};

test("fromHome maps the home slice onto the UI payload", () => {
  const h = D.fromHome(tiny);
  const a = h.byId.a;
  assert.equal(a.thumb, "https://plugins.omarchy.org/assets/a.webp");
  assert.equal(a.full, "https://plugins.omarchy.org/assets/a-big.webp");
  assert.equal(a.updated, "2026-09-01", "falls back to gh.lastCommit");
  assert.equal(a.listed, "2026-01-02");
  assert.equal(a.ini, "AW");
  assert.equal(a.risk, 4);
  assert.deepEqual(a.criteria.checked, ["no-exec"]);
  assert.ok(a.complete);
  assert.equal(h.byId.b.verdict, "unreviewed", "unknown -> unreviewed");
  assert.equal(h.byId.b.cat, "Other");
  assert.equal(h.byId.b.thumb, "https://cdn.example/b.png", "absolute URLs kept");
  assert.deepEqual(h.counts, { safe: 1, caution: 0, risky: 0, blocked: 1, unreviewed: 1, images: 2 });
  assert.equal(h.catCounts.Widgets, 2);
  assert.equal(h.meta.apiBase, "api");
  assert.equal(h.meta.version, 9);
});

test("blocked never reaches shelves or the hero; unknown ids are dropped", () => {
  const h = D.fromHome(tiny);
  const ids = (rs) => rs.map((p) => p.id);
  assert.deepEqual(ids(h.shelves.top), ["a", "b"]);
  assert.deepEqual(ids(h.shelves.trending), []);
  assert.deepEqual(ids(h.byCategory.Widgets), ["a"]);
  assert.deepEqual(ids(h.heroes), ["a", "b"], "heroes need an image (full, else thumb)");
  assert.equal(D.fromHome(null).total, 0);
});

test("the real home slice: small, shelves full, heroes with images", () => {
  const h = D.fromHome(homeDoc);
  assert.ok(devHomeText().length < 200_000, "home stays small");
  assert.ok(h.total > 4500);
  assert.ok(h.heroes.length > 0 && h.heroes.length <= D.HERO_COUNT);
  assert.equal(h.shelves.top.length, D.SHELF_SIZE);
  assert.ok(h.catCounts.Widgets > 1000);
  assert.ok(h.meta.dev);
  for (const shelf of Object.values(h.shelves)) for (const p of shelf) assert.notEqual(p.verdict, "blocked");
});

test("search columns -> table and records agree with the home rows", () => {
  const t = D.fromSearch(searchDoc, homeDoc.imageBase);
  assert.equal(t.n, homeDoc.total);
  const h = D.fromHome(homeDoc);
  for (const full of h.shelves.top.slice(0, 6)) {
    const r = D.record(t, t.byId[full.id]);
    assert.equal(r.complete, false);
    for (const k of ["id", "name", "author", "cat", "kind", "verdict", "basis", "rank", "stars", "vel30", "thumb", "repo", "commit", "risk", "verif", "listed", "updated", "accent", "ini"])
      assert.deepEqual(r[k], full[k], `${full.id}.${k}`);
    assert.deepEqual(r.providers, full.providers);
    assert.deepEqual(r.criteria, full.criteria);
  }
  const om = D.record(t, t.byId.omamail);
  assert.equal(om.verdict, "caution");
  assert.equal(om.risk, 13);
  assert.deepEqual(om.criteria.failed.sort(), ["no-exec", "no-network"]);
  assert.equal(om.providers.opc, "caution");
  assert.equal(om.report, "plugins/omamail.json");
  assert.match(om.repo, /^https:\/\/github\.com\//);
  for (let i = 0; i < t.n; i += 97) {
    const r = D.record(t, i);
    assert.ok(["safe", "caution", "risky", "blocked", "unreviewed"].includes(r.verdict));
    assert.ok(r.desc.length <= 200);
  }
});

test("fromDetail maps the aggregated view and our report", () => {
  const d = D.fromDetail(devDetail("omamail"), homeDoc.providers, homeDoc.imageBase);
  assert.equal(d.combined.verdict, "caution");
  assert.equal(d.providers.length, 2);
  const opc = d.providers.find((p) => p.id === "opc");
  assert.match(opc.name, /omarchy-plugin-check/);
  assert.equal(opc.signed, false, "unsigned-dev is not a signature");
  assert.deepEqual(d.criteria.notChecked, ["reviewed-by-human"]);
  assert.ok(d.listing.complete && d.listing.id === "omamail");
  assert.ok(d.listing.license !== undefined && d.listing.c90 !== undefined);
  assert.ok(d.weeks.some((w) => w > 0), "weekly commits from the collector");
  assert.ok(d.hasReport);
  assert.equal(d.risk, 13);
  assert.ok(d.findings.length > 0 && d.findings.length <= 12);
  assert.ok(d.findingCount >= d.findings.length);
  assert.equal(d.caps.processExec, "med");
  assert.ok(d.hosts.some((h) => h.host === "accounts.google.com"));
  assert.equal(d.weeks.length, 52);
  assert.ok(d.deps !== undefined && d.quality.loc > 0);
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
