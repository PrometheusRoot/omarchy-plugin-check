// The ONE adapter between snapshot files and the UI model (store/SNAPSHOT-FIELDS.md).
// Switching the store to the published store.json, or following a schema change, touches
// this file only: QML and the other libs read the model below, never snapshot fields.
//
// Input: store.json (spec/schemas/store.schema.json, draft v1) and the per-plugin
// aggregated view at apiBase + plugin.report (api-plugin.schema.json; our own provider
// row carries the rich opsec report in row.detail.report).

export var HERO_COUNT = 6;

export function str(v) {
  return v === null || v === undefined ? "" : String(v);
}

export function nul(v) {
  return v === undefined ? null : v;
}

export function abs(base, path) {
  if (!path) return "";
  path = String(path);
  if (/^https:\/\//.test(path)) return path;
  if (!base) return "";
  return base.replace(/\/+$/, "") + "/" + path.replace(/^\/+/, "");
}

export function initials(name) {
  var w = str(name).replace(/[^A-Za-z0-9 ]+/g, " ").trim().split(/\s+/);
  if (w.length > 1 && w[1]) return (w[0][0] + w[1][0]).toUpperCase();
  return str(w[0] || "?").slice(0, 2).toUpperCase();
}

// store.json combined verdict -> UI outcome. "unknown" (nobody trusted reviewed this
// commit) is shown as "unreviewed".
export function outcome(v) {
  var c = v && v.combined;
  return c === "safe" || c === "caution" || c === "risky" || c === "blocked" ? c : "unreviewed";
}

export function mapPlugin(s, imageBase) {
  var gh = s.gh || {};
  var mkt = s.mkt || {};
  var v = s.verdict || {};
  var img = s.img || {};
  return {
    id: str(s.id),
    name: str(s.name) || str(s.id),
    author: str(s.author),
    desc: str(s.desc),
    cat: str(s.cat) || "Other",
    kind: str(s.kind),
    tags: s.tags || [],
    repo: str(s.repo),
    path: str(s.path),
    install: str(s.install),
    license: str(s.license),
    version: str(s.version),
    listingState: str(s.state) || "listed",
    verif: str(s.verif) || "unverified",
    listed: str(s.listed).slice(0, 10),
    updated: str(s.updated || gh.lastCommit).slice(0, 10),
    thumb: abs(imageBase, img.thumb),
    full: abs(imageBase, img.full || img.thumb),
    gallery: (s.gallery || []).slice(0, 8),
    ini: str(s.ini) || initials(s.name || s.id),
    accent: str(s.accent),
    stars: gh.stars || 0,
    vel30: nul(gh.vel30),
    c90: nul(gh.c90),
    contrib: nul(gh.contrib),
    bus: nul(gh.bus),
    rel180: nul(gh.rel180),
    lastRelease: nul(gh.lastRelease),
    respH: nul(gh.respH),
    archived: !!gh.archived,
    views: s.mkt ? nul(mkt.views) : null,
    copies: s.mkt ? nul(mkt.copies) : null,
    hearts: s.mkt ? nul(mkt.hearts) : null,
    quality: nul(s.quality),
    rank: nul(s.rank),
    rankScore: nul(s.score),
    fac: s.fac || [],
    verdict: outcome(v),
    basis: str(v.basis) || "none",
    contested: !!v.contested,
    commit: nul(v.commit),
    providers: v.providers || {},
    risk: v.risk === undefined ? null : v.risk,
    criteria: v.criteria || null,
    report: typeof s.report === "string" ? s.report : s.report ? "plugins/" + str(s.id) + ".json" : null
  };
}

export function ids(list, byId, plugins, dropBlocked) {
  var out = [];
  for (var i = 0; list && i < list.length; i++) {
    var ix = byId[list[i]];
    if (ix === undefined) continue;
    if (dropBlocked && plugins[ix].verdict === "blocked") continue;
    out.push(ix);
  }
  return out;
}

// Returns the UI model. Blocked plugins never appear on shelves or the hero (store
// approval note), whatever the snapshot says; they stay searchable.
export function fromSnapshot(snap) {
  snap = snap || {};
  var imageBase = str(snap.imageBase);
  var raw = snap.plugins || [];
  var plugins = new Array(raw.length);
  var byId = {};
  for (var i = 0; i < raw.length; i++) {
    plugins[i] = mapPlugin(raw[i], imageBase);
    byId[plugins[i].id] = i;
  }
  var sh = snap.shelves || {};
  var byCat = {};
  for (var c in sh.byCategory || {}) byCat[c] = ids(sh.byCategory[c], byId, plugins, true);
  var top = ids(sh.top, byId, plugins, true);
  var heroes = [];
  for (var h = 0; h < top.length && heroes.length < HERO_COUNT; h++)
    if (plugins[top[h]].full) heroes.push(top[h]);
  var counts = { safe: 0, caution: 0, risky: 0, blocked: 0, unreviewed: 0, images: 0 };
  for (var k = 0; k < plugins.length; k++) {
    counts[plugins[k].verdict]++;
    if (plugins[k].thumb) counts.images++;
  }
  var cat = snap.catalog || {};
  var rk = snap.ranking || {};
  return {
    meta: {
      version: snap.version || 0,
      generatedAt: str(snap.generatedAt),
      expires: str(snap.expires),
      dev: !!snap.dev,
      catalogAt: str(cat.generatedAt),
      catalogPlugins: cat.plugins || plugins.length,
      imageBase: imageBase,
      apiBase: str(snap.apiBase),
      providers: snap.providers || [],
      factors: rk.factors || [],
      gates: rk.gates || {},
      rankingVersion: str(rk.version),
      statsAt: str(rk.statsGeneratedAt)
    },
    plugins: plugins,
    byId: byId,
    heroes: heroes,
    shelves: {
      top: top,
      trending: ids(sh.trending, byId, plugins, true),
      "new": ids(sh["new"], byId, plugins, true),
      updated: ids(sh.updated, byId, plugins, true),
      safePicks: ids(sh.safePicks, byId, plugins, true),
      byCategory: byCat
    },
    categories: snap.categories || [],
    counts: counts
  };
}

export function catCount(model, name) {
  for (var i = 0; i < model.categories.length; i++)
    if (model.categories[i].name === name) return model.categories[i].count;
  return 0;
}

// Per-plugin detail (lazy). view = api/v1/plugins/<id>.json.
export function fromDetail(view, providersMeta) {
  view = view || {};
  var tiers = {};
  for (var t = 0; t < (providersMeta || []).length; t++) tiers[providersMeta[t].id] = providersMeta[t];
  var rows = view.providers || [];
  var providers = [];
  var report = null;
  for (var i = 0; i < rows.length; i++) {
    var r = rows[i];
    var meta = tiers[r.provider] || {};
    var crit = r.criteria || {};
    providers.push({
      id: str(r.provider),
      name: str(meta.name) || str(r.provider),
      tier: str(r.tier),
      signed: r.verification === "sigstore",
      verification: str(r.verification),
      verdict: str(r.verdict),
      effective: str(r.effectiveVerdict),
      adjustments: r.adjustments || [],
      counted: r.counted !== false,
      when: str(r.timeReviewed).slice(0, 10),
      commit: nul(r.commit),
      summary: str(r.summary),
      checked: crit.checked || [],
      failed: crit.failed || []
    });
    if (!report && r.detail && r.detail.report) report = r.detail.report;
  }
  var c = view.combined || {};
  var d = {
    combined: { verdict: outcome({ combined: c.verdict }), basis: str(c.basis), contested: !!c.contested, commits: c.commits || [], reasons: c.reasons || [] },
    providers: providers,
    hasReport: !!report,
    weeks: view.activity && view.activity.weeks ? view.activity.weeks : [],
    gallery: view.gallery || []
  };
  if (report) mapReport(d, report);
  else rowFindings(d, rows);
  return d;
}

var SEV_ORDER = { critical: 0, high: 1, medium: 2, low: 3, info: 4 };

// Without our rich report (published API rows): evidence comes from the counted rows'
// predicate findings ({category, severity, confidence, message, locations[]}).
function rowFindings(d, rows) {
  var all = [];
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].counted === false) continue;
    var fs = rows[i].findings || [];
    for (var k = 0; k < fs.length; k++) all.push(fs[k]);
  }
  all.sort(function (a, b) { return (SEV_ORDER[a.severity] === undefined ? 5 : SEV_ORDER[a.severity]) - (SEV_ORDER[b.severity] === undefined ? 5 : SEV_ORDER[b.severity]) || (b.confidence || 0) - (a.confidence || 0); });
  d.findingCount = all.length;
  d.findings = all.slice(0, 12).map(function (f) {
    var loc = (f.locations || [])[0] || {};
    return { sev: str(f.severity), msg: str(f.message), where: loc.path ? str(loc.path) + (loc.startLine ? ":" + loc.startLine : "") : "—", hard: false };
  });
  var trusted = null;
  for (var j = 0; j < d.providers.length; j++) if (d.providers[j].tier === "core" || d.providers[j].tier === "verified") { trusted = d.providers[j]; break; }
  if (trusted) {
    d.criteria = { checked: trusted.checked, failed: trusted.failed };
    d.reviewedCommit = str(trusted.commit);
    d.reviewedAt = trusted.when;
  }
}

export function mapReport(d, r) {
  var v = r.verdict || {};
  d.risk = v.score === undefined ? null : v.score;
  d.summary = str(v.summary);
  d.reasons = v.reasons || [];
  d.hardFails = (v.hardFails || []).map(function (h) { return typeof h === "string" ? h : str(h.message || h.id); });
  var crit = v.criteria || {};
  d.criteria = { checked: crit.checked || [], failed: crit.failed || [] };
  d.reviewedCommit = r.review ? str(r.review.commit) : "";
  d.reviewedAt = r.review ? str(r.review.reviewedAt).slice(0, 10) : "";
  d.aiModel = r.review ? str(r.review.aiModel) : "";
  var ai = r.ai && r.ai.pass1 && r.ai.pass1.output ? r.ai.pass1.output : null;
  d.ai = ai ? str(ai.summary) : "";
  d.guardOk = !!(r.ai && r.ai.guard && r.ai.guard.canaryOk && !r.ai.guard.disallowedToolUse);
  d.oneLiner = r.whatItDoes ? str(r.whatItDoes.oneLiner) : "";
  var caps = r.capabilities || {};
  d.caps = {};
  for (var k in caps) d.caps[k] = caps[k] && caps[k].level ? caps[k].level : "none";
  d.areas = r.systemAreas ? r.systemAreas.touched || [] : [];
  d.hosts = (r.network && r.network.hosts ? r.network.hosts : []).map(function (h) { return { host: str(h.host), schemes: (h.schemes || []).join(", ") }; });
  var perf = r.performance || {};
  d.perf = {
    timers: (perf.timers || []).length,
    minInterval: (perf.timers || []).reduce(function (m, x) { return x.intervalMs && (m === null || x.intervalMs < m) ? x.intervalMs : m; }, null),
    spawns: perf.estSpawnsPerMin === undefined ? null : perf.estSpawnsPerMin,
    keepLoaded: !!perf.keepLoaded,
    largeAssets: (perf.largeAssets || []).length
  };
  var deps = r.dependencies || {};
  var vulns = deps.vulnerabilities || [];
  d.deps = (deps.packages || []).map(function (p) {
    var adv = vulns.filter(function (x) { return x.package === p.name; }).map(function (x) { return str(x.id) + " · " + str(x.severity); });
    return { name: str(p.name), version: str(p.version), eco: str(p.ecosystem), adv: adv.join(", ") };
  }).concat((deps.systemPackages || []).map(function (s) { return { name: str(s.name || s) + " (system)", version: str(s.version) || "—", eco: "sys", adv: "" }; }));
  var sev = { critical: 0, high: 1, medium: 2, low: 3, info: 4 };
  d.findings = (r.findings || []).slice().sort(function (a, b) { return (sev[a.severity] || 5) - (sev[b.severity] || 5) || (b.confidence || 0) - (a.confidence || 0); })
    .slice(0, 12).map(function (f) { return { sev: str(f.severity), msg: str(f.message), where: f.path ? str(f.path) + (f.line ? ":" + f.line : "") : "—", hard: !!f.hardFail }; });
  d.findingCount = (r.findings || []).length;
  var q = r.codeQuality || {};
  d.quality = {
    loc: q.loc ? q.loc.total : null,
    langs: q.loc ? (q.loc.byLanguage || []).slice(0, 4).map(function (x) { return x.language; }) : [],
    lint: (q.lint || []).map(function (x) { return x.tool + " " + x.errors + "e/" + x.warnings + "w"; }),
    tests: q.tests ? !!q.tests.present : false,
    readme: q.docs ? !!q.docs.readme : false,
    license: q.license ? str(q.license.spdx) : ""
  };
  var sc = r.supplyChain || {};
  d.supply = { signedRatio: nul(sc.signedCommitRatio), busFactor: nul(sc.busFactor), ageDays: nul(sc.repoAgeDays), unpinned: (sc.unpinnedRemoteFetches || []).length };
  var m = r.maintenance || {};
  d.maintenance = { lastCommit: str(m.lastCommitAt).slice(0, 10), c90: nul(m.commits90d), contrib: nul(m.contributors), release: str(m.latestRelease) };
  d.ecosystems = [];
  for (var e = 0; e < d.deps.length; e++) if (d.ecosystems.indexOf(d.deps[e].eco) === -1) d.ecosystems.push(d.deps[e].eco);
}

// `id sha` per line from the installed-plugins probe (Installer.qml).
export function parseInstalled(text) {
  var out = {};
  var lines = str(text).split("\n");
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].trim().match(/^([A-Za-z0-9][A-Za-z0-9._-]*)(?:\s+([0-9a-f]{7,40}))?$/);
    if (m) out[m[1]] = { sha: m[2] || "" };
  }
  return out;
}
