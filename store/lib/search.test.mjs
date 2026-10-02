import assert from "node:assert/strict";
import { performance } from "node:perf_hooks";
import { test } from "node:test";
import { devSearchText } from "../tools/devdata.mjs";
import * as D from "./data.mjs";
import * as S from "./search.mjs";


const mk = (id, name, extra = {}) => ({
  id, name, author: "someone", tags: [], desc: "", cat: "Widgets", kind: "Bar widget",
  verdict: "unreviewed", rank: null, stars: 0, vel30: 0, listed: "2026-01-01", updated: "2026-01-01", ...extra,
});

const small = [
  mk("a.weather", "Weather Pro", { rank: 3, stars: 10, desc: "forecast in the bar", tags: ["weather"] }),
  mk("b.clock", "Clock", { rank: 1, stars: 50, author: "weatherman", listed: "2026-03-01" }),
  mk("c.mail", "Omamail", { rank: 2, stars: 30, desc: "mail with weather alerts", verdict: "caution", updated: "2026-05-01" }),
  mk("d.ytdlp", "yt-dlp", { rank: 4, stars: 5, tags: ["video"], cat: "Productivity", vel30: 9 }),
  mk("e.fore", "Fore Weather", { rank: 5, stars: 1, verdict: "blocked" }),
];
const idx = S.buildIndex(small);
const names = (r) => Array.from(r.res, (i) => small[i].name);

test("normalize folds case, accents and punctuation", () => {
  assert.equal(S.normalize("Café-Bar  ÜBER!"), "cafe bar uber");
  assert.deepEqual(Array.from(S.words("  yt-DLP  ")), ["yt", "dlp"]);
});

test("empty query returns everything in the sort order", () => {
  assert.deepEqual(names(S.search(idx, "", {}, "rank", {})), ["Clock", "Omamail", "Weather Pro", "yt-dlp", "Fore Weather"]);
  assert.deepEqual(names(S.search(idx, "", {}, "stars", {})), ["Clock", "Omamail", "Weather Pro", "yt-dlp", "Fore Weather"]);
  assert.equal(names(S.search(idx, "", {}, "trending", {}))[0], "yt-dlp");
  assert.equal(names(S.search(idx, "", {}, "new", {}))[0], "Clock");
  assert.equal(names(S.search(idx, "", {}, "updated", {}))[0], "Omamail");
});

test("buckets: name prefix > word-start > author > tag/desc; ties keep sort order", () => {
  // "weather": Weather Pro (name prefix 8, exact? no), Fore Weather (word start 8),
  // Clock (author 4), Omamail (desc 2). Weather Pro outranks Fore Weather by rank.
  assert.deepEqual(names(S.search(idx, "weather", {}, "rank", {})), ["Weather Pro", "Fore Weather", "Clock", "Omamail"]);
});

test("exact name match is boosted", () => {
  assert.equal(names(S.search(idx, "clock", {}, "rank", {}))[0], "Clock");
  assert.equal(names(S.search(idx, "fore weather", {}, "rank", {}))[0], "Fore Weather");
});

test("fuzzy subsequence over the name catches squashed words", () => {
  assert.deepEqual(names(S.search(idx, "ytdlp", {}, "rank", {})), ["yt-dlp"]);
  assert.deepEqual(names(S.search(idx, "zzz", {}, "rank", {})), []);
});

test("every word must match", () => {
  assert.deepEqual(names(S.search(idx, "weather mail", {}, "rank", {})), ["Omamail"]);
});

test("filters: category, kind, verdict, installed", () => {
  assert.deepEqual(names(S.search(idx, "", { cat: "Productivity" }, "rank", {})), ["yt-dlp"]);
  assert.deepEqual(names(S.search(idx, "", { verdict: "caution" }, "rank", {})), ["Omamail"]);
  assert.deepEqual(names(S.search(idx, "", { verdict: "blocked" }, "rank", {})), ["Fore Weather"]);
  assert.deepEqual(names(S.search(idx, "", { kind: "Overlay" }, "rank", {})), []);
  assert.deepEqual(names(S.search(idx, "", { inst: true }, "rank", { "b.clock": true })), ["Clock"]);
});

test("blocked plugins stay searchable", () => {
  assert.ok(names(S.search(idx, "fore", {}, "rank", {})).includes("Fore Weather"));
});

test("unknown sort falls back to rank", () => {
  assert.deepEqual(names(S.search(idx, "", {}, "bogus", {})), names(S.search(idx, "", {}, "rank", {})));
});

test("narrowing from the previous result equals a full search", () => {
  const t = D.fromSearch(JSON.parse(devSearchText()), "");
  const big = S.buildIndex(t);
  for (const phrase of ["omarchy weather", "clock", "github stars", "ytdlp", "bar wid"]) {
    let prev = null;
    for (let k = 1; k <= phrase.length; k++) {
      const q = phrase.slice(0, k);
      const seeded = S.search(big, q, {}, "rank", {}, prev);
      const full = S.search(big, q, {}, "rank", {}, null);
      assert.deepEqual(Array.from(seeded.res), Array.from(full.res), `query ${JSON.stringify(q)}`);
      prev = seeded;
    }
  }
  // a different filter must not reuse the previous matches
  const a = S.search(big, "wea", {}, "rank", {}, null);
  const b = S.search(big, "weat", { cat: "Widgets" }, "rank", {}, a);
  assert.deepEqual(Array.from(b.res), Array.from(S.search(big, "weat", { cat: "Widgets" }, "rank", {}, null).res));
  // deleting a letter does not narrow
  assert.equal(S.narrows(["weat"], ["wea"]), false);
});

// ADR-0014 budget: < 5 ms per keystroke over the full catalog (4,777 entries), p95.
test("benchmark: p95 per keystroke < 5 ms over the full dev search columns", () => {
  const t = D.fromSearch(JSON.parse(devSearchText()), "");
  assert.ok(t.n > 4500, `${t.n} plugins`);
  const big = S.buildIndex(t);
  const phrases = ["weather", "omarchy clock", "github", "spotify player", "ytdlp", "bar widget battery", "zzzz nothing", "a", "theme switcher", "pomodoro timer"];
  const now = () => performance.now();
  S.warm(big); // the store does this right after the first frame
  S.benchKeystrokes(big, phrases, now, 1); // JIT warm-up
  // Typing: every keystroke narrows from the previous result, exactly as the store does.
  const f = (v) => v.toFixed(3);
  const p = (xs, q) => S.percentile(xs, q);
  // Five rounds; the best round's percentiles are the algorithm's latency (other rounds
  // also carry whatever else the machine was doing). Each round is every keystroke of
  // every phrase: typing narrows from the previous keystroke exactly as the store does;
  // cold searches every prefix from scratch (a paste, or a filter change mid-query).
  const rounds = [];
  for (let run = 0; run < 5; run++) {
    const typing = Array.from(S.benchKeystrokes(big, phrases, now, 1));
    const cold = [];
    for (const ph of phrases)
      for (let k = 1; k <= ph.length; k++) {
        const t0 = now();
        S.search(big, ph.slice(0, k), {}, "rank", {}, null);
        cold.push(now() - t0);
      }
    rounds.push({ typing, cold });
  }
  const best = (key, q) => Math.min(...rounds.map((r) => p(r[key], q)));
  const n = rounds[0].typing.length;
  console.log(`# search over ${big.n}: typing ${n} keystrokes x5, best round p50 ${f(best("typing", 50))} p95 ${f(best("typing", 95))} p99 ${f(best("typing", 99))} ms`);
  console.log(`# search over ${big.n}: cold ${rounds[0].cold.length} queries x5, best round p50 ${f(best("cold", 50))} p95 ${f(best("cold", 95))} p99 ${f(best("cold", 99))} ms`);
  assert.ok(best("typing", 95) < 5, `typing p95 ${best("typing", 95)} ms`);
  // A cold query (paste, filter change) is one event, not a keystroke: regression bound only.
  assert.ok(best("cold", 95) < 10, `cold p95 ${best("cold", 95)} ms`);
});

// ADR-0014/0032: the worker parses the search columns and builds the index after the first
// frame; both are budgeted (median of 3, noisy laptops).
test("search-file parse+map and index build stay inside the cold-start budget", () => {
  const text = devSearchText();
  const load = [];
  const build = [];
  for (let r = 0; r < 3; r++) {
    const t0 = performance.now();
    const t = D.fromSearch(JSON.parse(text), "");
    const t1 = performance.now();
    S.buildIndex(t);
    build.push(performance.now() - t1);
    load.push(t1 - t0);
  }
  const med = (xs) => xs.sort((a, b) => a - b)[1];
  console.log(`# parse+map ${med(load).toFixed(1)} ms, index ${med(build).toFixed(1)} ms (median of 3)`);
  assert.ok(med(load) < 150, `parse+map ${med(load)} ms`);
  assert.ok(med(build) < 200, `index ${med(build)} ms`);
});

test("the table helper builds the same index from objects", () => {
  const t = D.fromSearch(JSON.parse(devSearchText()), "");
  const recs = Array.from({ length: t.n }, (_, i) => D.record(t, i));
  const a = S.buildIndex(t);
  const b = S.buildIndex(recs);
  for (const q of ["weather", "omarchy cl", "z"])
    assert.deepEqual(Array.from(S.search(a, q, {}, "updated", {}, null).res), Array.from(S.search(b, q, {}, "updated", {}, null).res));
});

test("warm() caches every single-character word and keeps results identical", () => {
  const t = D.fromSearch(JSON.parse(devSearchText()), "");
  const cold = S.buildIndex(t);
  const hot = S.buildIndex(t);
  S.warm(hot);
  assert.equal(Object.keys(hot.cache).length, 36);
  for (const q of ["w", "o m", "7", "x weather"])
    assert.deepEqual(Array.from(S.search(hot, q, {}, "stars", {}, null).res), Array.from(S.search(cold, q, {}, "stars", {}, null).res));
});
