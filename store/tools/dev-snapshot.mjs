#!/usr/bin/env node
// Build the store's DEV snapshot (store/dev/store.json + store/dev/api/plugins/<id>.json)
// from a marketplace catalog.json and a directory of `opsec scan` outputs.
//
//   node store/tools/dev-snapshot.mjs --catalog catalog.json --reports DIR [--out store/dev]
//
// Shape: spec/schemas/store.schema.json (draft v1) plus the optional fields listed in
// store/SNAPSHOT-FIELDS.md. `dev: true`: GitHub activity and marketplace engagement the
// collector will provide are deterministic SAMPLE values here (stars, dates, listing data
// and the reviewed verdicts are real). Plugins without a report are unreviewed.
import { mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync, existsSync } from "node:fs";
import { join, resolve } from "node:path";
import { gzipSync } from "node:zlib";
import * as rank from "../lib/rank.mjs";


function arg(name, def) {
  const i = process.argv.indexOf(`--${name}`);
  return i > 0 ? process.argv[i + 1] : def;
}

const catalogPath = arg("catalog");
const reportsDir = arg("reports");
const out = resolve(arg("out", new URL("../dev", import.meta.url).pathname));
if (!catalogPath || !reportsDir) {
  console.error("usage: dev-snapshot.mjs --catalog catalog.json --reports DIR [--out DIR]");
  process.exit(2);
}

const catalog = JSON.parse(readFileSync(catalogPath, "utf8"));
const NOW = Date.parse(catalog.generatedAt);

// Deterministic sample values (same idea as the approved mockup), keyed by plugin id.
function h32(s) {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619) >>> 0;
  }
  return h;
}
const rnd = (id, salt) => (h32(`${id}|${salt}`) % 10000) / 10000;

// Reports: DIR/<id>/report.json (the AI-tiered run; `.noai` siblings are ignored).
const reports = new Map();
for (const name of readdirSync(reportsDir)) {
  const f = join(reportsDir, name, "report.json");
  if (name.endsWith(".noai") || !existsSync(f)) continue;
  const r = JSON.parse(readFileSync(f, "utf8"));
  reports.set(r.plugin.id, r);
}



const plugins = catalog.plugins.map((c) => {
  const r = reports.get(c.id);
  const id = c.id;
  const x = (s) => rnd(id, s);
  const stars = c.stars || 0;
  // why: every plugin gets sample activity, reviewed or not (ranking is review-neutral, ADR-0030).
  const gh = {
    stars,
    vel30: stars > 0 ? Math.round(stars * (0.04 + 0.45 * x("vel"))) : x("vel") < 0.25 ? 1 : 0,
    lastCommit: c.repositoryUpdatedAt || null,
    c90: Math.round(60 * x("c90") * x("c90b")),
    contrib: 1 + Math.floor(x("ct") * x("ct2") * 9),
    bus: 1,
    rel180: Math.floor(x("rel") * 6),
    lastRelease: c.repositoryRelease?.tag ?? null,
    issues: Math.floor(x("iss") * 12),
    respH: Math.round(2 + x("rsp") ** 2 * 236),
    archived: false,
    branch: c.upstreamObservedBranch || null,
  };
  const views = Math.round(stars * 40 * (0.5 + x("vw")) + 120 * x("vw2"));
  const verdict = r
    ? {
        combined: r.verdict.outcome,
        basis: "trusted",
        contested: false,
        commit: r.review.commit,
        providers: { opc: r.verdict.outcome, marketplace: "unknown" },
        risk: r.verdict.score,
        criteria: { checked: r.verdict.criteria.checked, failed: r.verdict.criteria.failed },
      }
    : { combined: "unknown", basis: "none", contested: false, commit: null, providers: { marketplace: "unknown" } };
  return {
    id,
    name: c.name,
    author: c.author ?? null,
    desc: (c.description || "").slice(0, 1000),
    cat: c.category ?? null,
    kind: c.kind ?? null,
    tags: (c.tags || []).slice(0, 20),
    repo: c.repo ?? null,
    install: c.installAvailable ? c.installCommand || "" : "",
    license: c.license ?? null,
    version: c.version ?? null,
    state: "listed",
    verif: c.verificationStatus ?? null,
    listed: c.listedAt ?? c.addedAt ?? null,
    updated: c.repositoryUpdatedAt ?? null,
    img: c.previewThumbnail
      ? { thumb: c.previewThumbnail, full: c.previewImage || c.previewThumbnail, w: c.previewThumbnailWidth || 720, h: c.previewThumbnailHeight || 405 }
      : null,
    gallery: [],
    gh,
    mkt: { views, copies: Math.round(views * (0.08 + 0.2 * x("cp"))), hearts: Math.round(stars * 0.6 * (0.3 + x("ht"))) },
    rank: null,
    score: null,
    fac: [],
    verdict,
    report: r ? `plugins/${id}.json` : null,
    // optional fields (SNAPSHOT-FIELDS.md "proposed")
    ini: c.initials || undefined,
    accent: c.accent || undefined,
  };
});

// Ranking (lib/rank.mjs mirrors the collector's ranking-v2; the collector owns it).
const view = plugins.map((p) => ({
  id: p.id, stars: p.gh.stars, vel30: p.gh.vel30, updated: p.updated, c90: p.gh.c90, contrib: p.gh.contrib, bus: p.gh.bus,
  rel180: p.gh.rel180, respH: p.gh.respH, views: p.mkt.views, copies: p.mkt.copies, hearts: p.mkt.hearts, verif: p.verif,
  verdict: p.verdict.combined === "unknown" ? "unreviewed" : p.verdict.combined,
}));
const ranked = rank.computeRanking(view, NOW);
view.forEach((v, i) => {
  plugins[i].rank = v.rank;
  plugins[i].score = v.rankScore;
  plugins[i].fac = Array.from(v.fac);
});

const visible = plugins.filter((p) => p.verdict.combined !== "blocked");
const take = (arr, n) => arr.slice(0, n).map((p) => p.id);
const byRank = [...visible].sort((a, b) => (a.rank ?? 1e9) - (b.rank ?? 1e9));
const byCategory = {};
for (const p of byRank) {
  const c = p.cat || "Other";
  (byCategory[c] ||= []).length < 30 && byCategory[c].push(p.id);
}
const cats = new Map();
for (const p of plugins) cats.set(p.cat || "Other", (cats.get(p.cat || "Other") || 0) + 1);

const snapshot = {
  schemaVersion: 1,
  kind: "omarchy-plugin-check/store",
  version: Math.floor(NOW / 1000),
  generatedAt: new Date(NOW).toISOString(),
  expires: new Date(NOW + 7 * 864e5).toISOString(),
  dev: true,
  catalog: { generatedAt: catalog.generatedAt, plugins: plugins.length, retired: 0, builtin: 0 },
  imageBase: "https://plugins.omarchy.org",
  apiBase: "api",
  providers: [
    { id: "opc", name: "omarchy-plugin-check", tier: "core", verification: "unsigned-dev", rows: reports.size },
    { id: "marketplace", name: "plugins.omarchy.org", tier: "unsigned", verification: "unsigned", rows: plugins.length },
  ],
  ranking: {
    version: "ranking-v2-dev",
    factors: rank.FACTORS.map((f) => ({ id: f.id, label: f.label, weight: f.weight })),
    gates: { ...rank.GATES },
    statsGeneratedAt: null,
  },
  shelves: {
    top: take(byRank, 100),
    trending: take([...visible].sort((a, b) => b.gh.vel30 - a.gh.vel30), 30),
    new: take([...visible].sort((a, b) => String(b.listed).localeCompare(String(a.listed))), 30),
    updated: take([...visible].sort((a, b) => String(b.updated).localeCompare(String(a.updated))), 30),
    safePicks: take(byRank.filter((p) => p.verdict.combined === "safe"), 30),
    byCategory,
  },
  categories: [...cats].map(([name, count]) => ({ name, count })).sort((a, b) => b.count - a.count),
  plugins,
};

// Per-plugin aggregated views (api-plugin.schema.json draft) with our report as detail.
function trimReport(r) {
  return {
    verdict: r.verdict,
    review: { commit: r.review.commit, reviewedAt: r.review.reviewedAt, aiModel: r.review.aiModel },
    whatItDoes: { oneLiner: r.whatItDoes?.oneLiner ?? "" },
    capabilities: Object.fromEntries(Object.entries(r.capabilities || {}).map(([k, v]) => [k, { level: v.level }])),
    systemAreas: { touched: r.systemAreas?.touched ?? [] },
    network: { hosts: (r.network?.hosts ?? []).map((h) => ({ host: h.host, schemes: h.schemes })) },
    performance: r.performance,
    dependencies: r.dependencies,
    findings: (r.findings || []).map((f) => ({ severity: f.severity, confidence: f.confidence, message: f.message, path: f.path, line: f.line, hardFail: f.hardFail })),
    codeQuality: r.codeQuality,
    supplyChain: r.supplyChain,
    maintenance: r.maintenance,
    ai: { pass1: { output: { summary: r.ai?.pass1?.output?.summary ?? "" } }, guard: r.ai?.guard ?? null },
  };
}

rmSync(join(out, "api"), { recursive: true, force: true });
mkdirSync(join(out, "api", "plugins"), { recursive: true });
for (const [id, r] of reports) {
  const p = plugins.find((x) => x.id === id);
  if (!p) continue;
  const weeks = Array.from({ length: 52 }, (_, i) => {
    const age = 51 - i;
    const base = p.gh.stars > 50 ? 6 : 2;
    return Math.max(0, Math.round(base * Math.exp(-age / 18) * (0.4 + rnd(id, `c${i}`) * 1.6)));
  });
  const apiView = {
    schemaVersion: 1,
    id,
    name: p.name,
    repo: p.repo,
    listingState: "listed",
    marketplaceUrl: `https://plugins.omarchy.org/plugin.html?id=${encodeURIComponent(id)}`,
    combined: { verdict: r.verdict.outcome, basis: "trusted", contested: false, commits: [r.review.commit], reasons: r.verdict.reasons || [] },
    providers: [
      {
        provider: "opc", tier: "core", verification: "unsigned-dev", commit: r.review.commit, verdict: r.verdict.outcome,
        effectiveVerdict: r.verdict.outcome, adjustments: [], counted: true, timeReviewed: r.review.reviewedAt,
        summary: (r.verdict.summary || "").slice(0, 200), criteria: { checked: r.verdict.criteria.checked, failed: r.verdict.criteria.failed },
        detail: { report: trimReport(r) },
      },
      {
        provider: "marketplace", tier: "unsigned", verification: "unsigned", commit: r.plugin.marketplace?.listingValidatedCommit ?? null,
        verdict: "unknown", effectiveVerdict: "unknown", adjustments: [], counted: false, timeReviewed: null,
        summary: `baseline ${r.plugin.marketplace?.baselineOutcome ?? "unknown"} · 5 blocking patterns · not bound to a commit`,
        criteria: { checked: [], failed: [] },
      },
    ],
    activity: { weeks },
  };
  writeFileSync(join(out, "api", "plugins", `${id}.json`), `${JSON.stringify(apiView)}\n`);
}

const text = `${JSON.stringify(snapshot)}\n`;
writeFileSync(join(out, "store.json"), text);
// why: the gz is what is committed (0.9 MB vs 5.3 MB); mtime-free so rebuilds are byte-stable.
writeFileSync(join(out, "store.json.gz"), gzipSync(text, { level: 9 }));
console.log(`dev snapshot: ${plugins.length} plugins, ${reports.size} reviewed, top ${ranked[0]} -> ${join(out, "store.json")}`);
