// The ONE adapter between snapshot files and the UI model (store/SNAPSHOT-FIELDS.md).
// Following a schema change touches this file only: QML and the other libs read the model
// below, never snapshot fields.
//
// Input: the client bundle (ADR-0032), verified by bin/omarchy-plugin-store-verify before any
// of it is parsed: store-home.json (shelves + the rows they show, store.json row format) on
// the GUI thread for the first frame; store-search.json (parallel columns) in the worker;
// per-plugin detail documents (api-plugin.schema.json: listing, activity, provider rows, our
// row's detail.report) lazily.

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

var VERDICTS = ["safe", "caution", "risky", "blocked", "unreviewed"];
var FLAG = { contested: 1, archived: 2, noInstall: 4, customInstall: 8, retired: 16, builtin: 32, detail: 64 };

function meta(doc) {
  var cat = doc.catalog || {};
  var rk = doc.ranking || {};
  return {
    version: doc.version || 0,
    generatedAt: str(doc.generatedAt),
    expires: str(doc.expires),
    dev: !!doc.dev,
    catalogAt: str(cat.generatedAt),
    catalogPlugins: cat.plugins || doc.total || 0,
    imageBase: str(doc.imageBase),
    apiBase: str(doc.apiBase),
    providers: doc.providers || [],
    factors: rk.factors || [],
    gates: rk.gates || {},
    rankingVersion: str(rk.version),
    statsAt: str(rk.statsGeneratedAt)
  };
}

function shelf(list, byId, limit) {
  var out = [];
  for (var i = 0; list && i < list.length && out.length < limit; i++) {
    var p = byId[list[i]];
    if (p && p.verdict !== "blocked") out.push(p);
  }
  return out;
}

export var SHELF_SIZE = 12;

// store-home.json -> the home payload the UI binds to (runs on the GUI thread: ~130 rows).
// Blocked plugins never appear on shelves or the hero (store approval note), whatever the
// snapshot says; they stay searchable.
export function fromHome(home) {
  home = home || {};
  var m = meta(home);
  var byId = {};
  var rows = home.plugins || [];
  for (var i = 0; i < rows.length; i++) {
    var p = mapPlugin(rows[i], m.imageBase);
    p.complete = true;
    byId[p.id] = p;
  }
  var sh = home.shelves || {};
  var top = shelf(sh.top, byId, 1e9);
  var heroes = [];
  for (var h = 0; h < top.length && heroes.length < HERO_COUNT; h++) if (top[h].full) heroes.push(top[h]);
  var byCat = {};
  for (var c in sh.byCategory || {}) byCat[c] = shelf(sh.byCategory[c], byId, SHELF_SIZE);
  var catCounts = {};
  var cats = home.categories || [];
  for (var k = 0; k < cats.length; k++) catCounts[cats[k].name] = cats[k].count;
  var n = home.counts || {};
  return {
    meta: m,
    counts: { safe: n.safe || 0, caution: n.caution || 0, risky: n.risky || 0, blocked: n.blocked || 0, unreviewed: n.unknown || 0, images: n.images || 0 },
    total: home.total || 0,
    catCounts: catCounts,
    heroes: heroes,
    shelves: {
      top: top.slice(0, SHELF_SIZE),
      trending: shelf(sh.trending, byId, SHELF_SIZE),
      "new": shelf(sh["new"], byId, SHELF_SIZE),
      updated: shelf(sh.updated, byId, SHELF_SIZE),
      safePicks: shelf(sh.safePicks, byId, SHELF_SIZE)
    },
    byCategory: byCat,
    byId: byId
  };
}

function pick(dict, ix) {
  return ix >= 0 && ix < dict.length ? dict[ix] : "";
}

// store-search.json -> the worker's table: the document's own arrays plus a few resolved
// string columns (references into the interned dictionaries, no new strings). Records are
// built per displayed row by record(); nothing here allocates per plugin except byId.
export function fromSearch(doc, imageBase) {
  var c = doc.cols;
  var d = doc.dict;
  var n = doc.n;
  var author = new Array(n);
  var cat = new Array(n);
  var kind = new Array(n);
  var verdict = new Array(n);
  var byId = {};
  for (var i = 0; i < n; i++) {
    author[i] = pick(d.author, c.author[i]);
    cat[i] = pick(d.cat, c.cat[i]) || "Other";
    kind[i] = pick(d.kind, c.kind[i]);
    verdict[i] = VERDICTS[c.verdict[i]] || "unreviewed";
    byId[c.id[i]] = i;
  }
  return {
    n: n, id: c.id, name: c.name, author: author, tags: c.tags, desc: c.desc, cat: cat, kind: kind,
    verdict: verdict, rank: c.rank, stars: c.stars, vel30: c.vel30, listed: c.listed, updated: c.updated,
    cols: c, dict: d, byId: byId, imageBase: str(imageBase)
  };
}

function providersOf(t, i) {
  var out = {};
  var pv = t.cols.prov;
  for (var k = 0; k < pv.length; k++) if (pv[k][i] >= 0) out[t.dict.providers[k]] = t.dict.verdict[pv[k][i]];
  return out;
}

function critOf(t, i) {
  var c = t.cols.critC[i];
  var f = t.cols.critF[i];
  if (!c && !f) return null;
  var out = { checked: [], failed: [] };
  for (var k = 0; k < t.dict.criteria.length; k++) {
    if (c & (1 << k)) out.checked.push(t.dict.criteria[k]);
    if (f & (1 << k)) out.failed.push(t.dict.criteria[k]);
  }
  return out;
}

// One UI record from the table (same fields as mapPlugin; `complete: false` = the detail
// document's listing fills in the rest: license, gallery, activity, marketplace stats...).
export function record(t, i) {
  var c = t.cols;
  var flags = c.flags[i];
  var repo = c.repo[i];
  var thumb = abs(t.imageBase, c.thumb[i]);
  return {
    id: c.id[i], name: c.name[i] || c.id[i], author: t.author[i], desc: c.desc[i], cat: t.cat[i], kind: t.kind[i],
    tags: c.tags[i] ? c.tags[i].split(" ") : [],
    repo: repo && !/^https:\/\//.test(repo) ? "https://github.com/" + repo : repo,
    path: "", install: "",
    license: "", version: "",
    listingState: flags & FLAG.retired ? "retired" : flags & FLAG.builtin ? "builtin" : "listed",
    verif: pick(t.dict.verif, c.verif[i]) || "unverified",
    listed: c.listed[i], updated: c.updated[i], thumb: thumb, full: thumb, gallery: [],
    ini: c.ini[i] || initials(c.name[i] || c.id[i]), accent: pick(t.dict.accent, c.accent[i]),
    stars: c.stars[i] || 0, vel30: nul(c.vel30[i]), c90: null, contrib: null, bus: null, rel180: null, lastRelease: null, respH: null,
    archived: !!(flags & FLAG.archived), views: null, copies: null, hearts: null, quality: null,
    rank: nul(c.rank[i]), rankScore: nul(c.score[i]), fac: [],
    verdict: t.verdict[i], basis: t.dict.basis[c.basis[i]] || "none", contested: !!(flags & FLAG.contested),
    commit: c.commit[i] || null, providers: providersOf(t, i), risk: nul(c.risk[i]), criteria: critOf(t, i),
    report: flags & FLAG.detail ? "plugins/" + c.id[i] + ".json" : null,
    complete: false
  };
}

// Per-plugin detail (lazy). view = api/v1/plugins/<id>.json. `listing` (the full store row)
// completes a record that came from the search columns.
export function fromDetail(view, providersMeta, imageBase) {
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
      failed: crit.failed || [],
      notChecked: crit.notChecked || []
    });
    if (!report && r.detail && r.detail.report) report = r.detail.report;
  }
  var c = view.combined || {};
  var d = {
    combined: { verdict: outcome({ combined: c.verdict }), basis: str(c.basis), contested: !!c.contested, commits: c.commits || [], reasons: c.reasons || [] },
    providers: providers,
    hasReport: !!report,
    weeks: view.activity && view.activity.weeks ? view.activity.weeks : [],
    gallery: view.listing && view.listing.gallery ? view.listing.gallery.slice(0, 8) : [],
    listing: null
  };
  if (view.listing) {
    d.listing = mapPlugin(view.listing, str(imageBase));
    d.listing.complete = true;
  }
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
    d.criteria = { checked: trusted.checked, failed: trusted.failed, notChecked: trusted.notChecked };
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
  d.criteria = { checked: crit.checked || [], failed: crit.failed || [], notChecked: crit.notChecked || [] };
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

// The installed-plugins probe (Installer.qml): `omarchy-plugin-check status --json` when the
// checker is installed (keyed by the listed id; `state` from Inst.statusState), else `id sha`
// per line from git. statusState is passed in so this module stays free of install logic.
export function parseInstalled(text, statusState) {
  var out = {};
  var t = str(text).trim();
  if (t.charAt(0) === "{") return parseStatus(t, statusState);
  var lines = str(text).split("\n");
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].trim().match(/^([A-Za-z0-9][A-Za-z0-9._-]*)(?:\s+([0-9a-f]{7,40}))?$/);
    if (m) out[m[1]] = { sha: m[2] || "" };
  }
  return out;
}

var ID_RE = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
var SHA_RE = /^[0-9a-f]{40}$/;

function parseStatus(text, statusState) {
  var out = {};
  var doc;
  try {
    doc = JSON.parse(text);
  } catch (e) {
    return out;
  }
  if (!doc || doc.kind !== "omarchy-plugin-check/status" || !Array.isArray(doc.plugins)) return out;
  for (var i = 0; i < doc.plugins.length; i++) {
    var e = doc.plugins[i] || {};
    var id = ID_RE.test(str(e.listedId)) ? e.listedId : str(e.id);
    if (!ID_RE.test(id) || out[id]) continue;
    var head = SHA_RE.test(str(e.head)) ? e.head : "";
    var rev = e.reviewed || {};
    out[id] = {
      sha: head.slice(0, 7),
      dir: str(e.dir),
      checkerState: str(e.state),
      commitMatch: typeof e.commitMatch === "boolean" ? e.commitMatch : null,
      treeMatch: typeof e.treeMatch === "boolean" ? e.treeMatch : null,
      moved: e.moved === true,
      origin: str(e.origin),
      repin: e.repin === "forward" || e.repin === "back" ? e.repin : null,
      reviewed: SHA_RE.test(str(rev.commit)) ? rev.commit : "",
      note: str(e.note)
    };
    if (statusState) out[id].state = statusState({ state: e.state, repin: out[id].repin, commitMatch: out[id].commitMatch, treeMatch: out[id].treeMatch });
  }
  return out;
}
