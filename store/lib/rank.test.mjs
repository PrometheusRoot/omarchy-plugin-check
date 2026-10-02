import assert from "node:assert/strict";
import { test } from "node:test";
import * as R from "./rank.mjs";

const NOW = Date.parse("2026-10-01T00:00:00Z");
const base = (id, extra = {}) => ({
  id, stars: 100, vel30: 10, updated: "2026-09-25", c90: 20, contrib: 3, bus: 1, rel180: 2, respH: 24,
  views: 1000, copies: 100, hearts: 10, verif: "unverified", quality: 70, verdict: "safe", ...extra,
});

test("weights sum to 100 and every factor has a source and detail", () => {
  assert.equal(R.FACTORS.reduce((a, f) => a + f.weight, 0), 100);
  for (const f of R.FACTORS) {
    assert.ok(f.source && f.label && f.id);
    assert.equal(typeof f.detail(base("x"), NOW), "string");
  }
});

test("contributions stay within [0, weight]; missing data contributes 0", () => {
  const full = R.contributions(base("x", { stars: 1e9, vel30: 1e9, c90: 1e9, contrib: 1e9, rel180: 1e9, respH: 0, views: 1e12, verif: "verified" }), NOW);
  R.FACTORS.forEach((f, i) => assert.ok(full[i] <= f.weight && full[i] >= 0, f.id));
  const empty = R.contributions({ id: "e", verdict: "safe" }, NOW);
  // unknown activity is 0; unknown issue response is neutral (0.5); unverified listing 0.3
  R.FACTORS.forEach((f, i) => assert.equal(empty[i], f.id === "verif" ? 1.5 : f.id === "issues" ? 4 : 0, f.id));
});

test("safety gates only demote: blocked never ranked, risky x0.6, review status neutral", () => {
  const ps = [base("safe"), base("caution", { verdict: "caution" }), base("risky", { verdict: "risky" }), base("unrev", { verdict: "unreviewed" }), base("blocked", { verdict: "blocked" })];
  const ids = R.computeRanking(ps, NOW);
  assert.equal(ids.includes("blocked"), false);
  const by = Object.fromEntries(ps.map((p) => [p.id, p]));
  assert.equal(by.blocked.rank, null);
  assert.equal(by.safe.rankScore, by.caution.rankScore);
  assert.ok(Math.abs(by.risky.rankScore - by.safe.rankScore * 0.6) < 0.05);
  assert.equal(by.unrev.rankScore, by.safe.rankScore, "ADR-0030: unreviewed is not demoted");
  assert.deepEqual(ids.slice(-1), ["risky"]);
  assert.deepEqual(ids.map((id) => by[id].rank), [1, 2, 3, 4]);
  assert.equal(R.gateOf("bogus"), 1);
});

test("ranking is deterministic on ties (stars, then id)", () => {
  const a = [base("b"), base("a")];
  assert.deepEqual(R.computeRanking(a, NOW), ["a", "b"]);
});

test("explain uses the snapshot's factor table and the plugin's contributions", () => {
  const p = base("x");
  R.computeRanking([p], NOW);
  const rows = R.explain(p, [{ id: "stars", label: "log(stars)", weight: 20 }, { id: "future", label: "new factor", weight: 5 }], NOW);
  assert.equal(rows.length, 2);
  assert.equal(rows[0].value, p.fac[0]);
  assert.ok(rows[0].pct > 0 && rows[0].pct <= 1);
  assert.equal(rows[0].detail, "★ 100");
  assert.equal(rows[1].source, "");
  assert.equal(R.explain(p, [], NOW).length, R.FACTORS.length);
});
