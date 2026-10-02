// Open ranking (docs/RANKING.md "ranking-v2", ADR-0029/0030): weighted sum of factors
// clamped to [0, 1], then a safety gate that only demotes. The collector computes rank for
// the published store.json and the store displays `ranking.factors` from it; this copy of
// the formula builds the dev snapshot and labels the explainer. Review-neutral: no factor
// or gate rewards being reviewed.

export function fmtInt(n) {
  var s = String(Math.round(n || 0));
  var out = "";
  while (s.length > 3) {
    out = "," + s.slice(-3) + out;
    s = s.slice(0, -3);
  }
  return s + out;
}

export function ageDays(iso, nowMs) {
  var t = iso ? Date.parse(iso) : NaN;
  return isFinite(t) ? Math.max(0, (nowMs - t) / 864e5) : null;
}

export function num(v) {
  return v === null || v === undefined || !isFinite(v) ? null : Number(v);
}

export function clamp01(x) {
  return x < 0 ? 0 : x > 1 ? 1 : x;
}

// id, label, weight, source, value(p, now) in [0,1] or null (= no data, contributes 0),
// detail(p, now) for the explainer.
export var FACTORS = [
  { id: "stars", label: "log(stars)", weight: 22, source: "github stars",
    value: function (p) { var s = num(p.stars); return s === null ? null : clamp01(Math.log(1 + s) / Math.log(2100)); },
    detail: function (p) { return "★ " + fmtInt(p.stars); } },
  { id: "velocity", label: "★ velocity 30d", weight: 16, source: "stars gained, 30 days",
    value: function (p) { var v = num(p.vel30); return v === null ? null : clamp01(Math.log(1 + v) / Math.log(401)); },
    detail: function (p) { return p.vel30 === null || p.vel30 === undefined ? "no data" : "+" + fmtInt(p.vel30) + " ★/30d"; } },
  { id: "recency", label: "commit recency", weight: 11, source: "days since last push, decay 45d",
    value: function (p, now) { var d = ageDays(p.updated, now); return d === null ? null : Math.exp(-d / 45); },
    detail: function (p, now) { var d = ageDays(p.updated, now); return d === null ? "no data" : "last push " + Math.round(d) + "d ago"; } },
  { id: "commits", label: "commits 90d", weight: 11, source: "commits in 90 days",
    value: function (p) { var c = num(p.c90); return c === null ? null : clamp01(c / 60); },
    detail: function (p) { return p.c90 === null || p.c90 === undefined ? "no data" : p.c90 + " commits"; } },
  { id: "contrib", label: "contributors", weight: 8, source: "distinct authors · bus factor",
    value: function (p) { var c = num(p.contrib); return c === null ? null : clamp01((c - 1) / 5); },
    detail: function (p) { return p.contrib === null || p.contrib === undefined ? "no data" : p.contrib + " · bus factor " + (p.bus || 1); } },
  { id: "releases", label: "release cadence", weight: 8, source: "tags in 6 months",
    value: function (p) { var r = num(p.rel180); return r === null ? null : clamp01(r / 4); },
    detail: function (p) { return p.rel180 === null || p.rel180 === undefined ? "no data" : p.rel180 + " tags / 6mo"; } },
  { id: "issues", label: "issue response", weight: 8, source: "median first response",
    value: function (p) { var h = num(p.respH); return h === null ? 0.5 : clamp01(1 - Math.log(Math.max(1, h)) / Math.log(240)); },
    detail: function (p) { var h = num(p.respH); return h === null ? "no issues · neutral" : "median " + (h < 48 ? Math.round(h) + "h" : Math.round(h / 24) + "d"); } },
  { id: "engage", label: "marketplace engagement", weight: 11, source: "marketplace views/copies/hearts",
    value: function (p) { var v = num(p.views); return v === null ? null : clamp01(Math.log(1 + v) / Math.log(100001)); },
    detail: function (p) { return p.views === null || p.views === undefined ? "no data" : fmtInt(p.views) + " views · " + fmtInt(p.copies) + " copies · " + fmtInt(p.hearts) + " ♥"; } },
  { id: "verif", label: "marketplace verification", weight: 5, source: "marketplace verification state",
    value: function (p) { return p.verif === "verified" ? 1 : 0.3; },
    detail: function (p) { return p.verif || "unverified"; } }
];

export var GATES = { safe: 1, caution: 1, unreviewed: 1, risky: 0.6, blocked: 0 };

export function factorById(id) {
  for (var i = 0; i < FACTORS.length; i++)
    if (FACTORS[i].id === id) return FACTORS[i];
  return null;
}

// Weighted contributions in FACTORS order.
export function contributions(p, nowMs) {
  var out = new Array(FACTORS.length);
  for (var i = 0; i < FACTORS.length; i++) {
    var v = FACTORS[i].value(p, nowMs);
    out[i] = v === null ? 0 : Math.round(v * FACTORS[i].weight * 100) / 100;
  }
  return out;
}

// Sets p.fac, p.rankScore, p.rank (null for blocked) on every plugin; returns ranked ids.
export function computeRanking(plugins, nowMs) {
  var ranked = [];
  for (var i = 0; i < plugins.length; i++) {
    var p = plugins[i];
    p.fac = contributions(p, nowMs);
    var raw = 0;
    for (var k = 0; k < p.fac.length; k++) raw += p.fac[k];
    var gate = GATES[p.verdict] === undefined ? GATES.unreviewed : GATES[p.verdict];
    p.rankScore = Math.round(raw * gate * 100) / 100;
    p.rank = null;
    if (gate > 0) ranked.push(p);
  }
  ranked.sort(function (a, b) { return b.rankScore - a.rankScore || (b.stars || 0) - (a.stars || 0) || (a.id < b.id ? -1 : 1); });
  for (var r = 0; r < ranked.length; r++) ranked[r].rank = r + 1;
  return ranked.map(function (x) { return x.id; });
}

// Rows for the "why #N" bars and the explainer table. `factors` = snapshot ranking.factors
// ([{id,label,weight}]); falls back to the built-in table.
export function explain(p, factors, nowMs) {
  factors = factors && factors.length ? factors : FACTORS;
  var rows = [];
  for (var i = 0; i < factors.length; i++) {
    var f = factors[i];
    var known = factorById(f.id);
    var c = p.fac && p.fac[i] !== undefined ? p.fac[i] : 0;
    rows.push({
      id: f.id, label: f.label, weight: f.weight, source: known ? known.source : "",
      value: c, pct: f.weight > 0 ? Math.max(0, Math.min(1, c / f.weight)) : 0,
      detail: known ? known.detail(p, nowMs) : ""
    });
  }
  return rows;
}

export function gateOf(verdict) {
  return GATES[verdict] === undefined ? GATES.unreviewed : GATES[verdict];
}
