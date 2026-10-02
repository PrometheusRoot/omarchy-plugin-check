// In-memory search over the snapshot (ADR-0014 budget: < 5 ms per keystroke over 4.5k;
// ADR-0026: runs in the store's WorkerScript, so a slow keystroke never drops a frame).
//
// Built once at load: one normalized haystack per plugin ("name author tags id desc", with
// the field boundaries recorded) and a character mask per name. Orderings, one per sort
// mode, are sorted once on first use. A keystroke never sorts and never allocates per
// plugin: it walks the active ordering once (O(n)); per candidate and query word ONE
// indexOf decides the match and, from the hit position, the best field (name word-start 8
// > name 6 > author 4 > tag 3 > text 2; a fuzzy name subsequence scores 1). A counting
// sort over the summed score ("bucketing") yields best match first, ties in sort order.
// Typing forward narrows: the walk only visits the previous matches (a longer word can
// only match a subset) and reuses the scores of words that did not change; single
// characters are pre-scored by warm().

export var SORTS = ["rank", "stars", "trending", "new", "updated"];
export var BUCKETS = 64;
export var PTS = { namePrefix: 8, name: 6, author: 4, tag: 3, text: 2, fuzzy: 1, exact: 8 };
var MAX_N = 8192; // orderings pack the tie position into 13 bits
var DESC = 1e8; // descending sorts use DESC - value
var UNSCORED = 255;
var CACHE_MAX = 96; // word score arrays kept (n bytes each)

// Accented Latin letters only (Latin-1 Supplement, Extended-A/B, Extended Additional): the
// rest of non-ASCII (dashes, emoji, CJK) can never match a [a-z0-9] query word, and calling
// fold() per em-dash costs ~0.5 s in QV4 over the catalog.
var ACCENTED = new RegExp("[\\u00C0-\\u024F\\u1E00-\\u1EFF]+", "g");
var MARKS = new RegExp("[\\u0300-\\u036f]", "g");

function fold(run) {
  return run.normalize ? run.normalize("NFD").replace(MARKS, "") : run;
}

// Lowercase, strip accents, collapse everything but [a-z0-9] (and newlines, which separate
// fields in buildIndex) into single spaces. Only accented Latin runs pay for NFD.
export function normalizeBlock(s) {
  s = String(s || "").replace(ACCENTED, fold).toLowerCase();
  return s.replace(/[^a-z0-9\n]+/g, " ").replace(/ ?\n ?/g, "\n");
}

export function normalize(s) {
  return normalizeBlock(String(s || "").replace(/\n/g, " ")).trim();
}

export function words(query) {
  var q = normalize(query);
  return q ? q.split(" ") : [];
}

function oneLine(s) {
  s = s ? String(s) : "";
  return s.indexOf("\n") === -1 ? s : s.replace(/\n/g, " ");
}

export function charMask(str) {
  var m = 0;
  for (var i = 0; i < str.length; i++) {
    var c = str.charCodeAt(i);
    if (c >= 97 && c <= 122) m |= 1 << (c - 97);
    else if (c >= 48 && c <= 57) m |= 1 << (26 + ((c - 48) % 6));
  }
  return m;
}

function numAsc(a, b) {
  return a - b;
}

// "2026-09-30..." -> sortable day count without Date.parse (cheap in QV4).
function dayKey(s) {
  if (!s || s.length < 10) return 0;
  return Number(s.slice(0, 4)) * 372 + Number(s.slice(5, 7)) * 31 + Number(s.slice(8, 10));
}

// Ascending sort of `key * MAX_N + tiePosition`; keys are integers in [0, 1e9) so the
// composite stays exact in a double.
// why: QV4 has no TypedArray.prototype.sort; a plain array of numbers still sorts without
// any object compares.
function orderBy(n, keyOf, tiePos) {
  var keys = new Array(n);
  for (var i = 0; i < n; i++) keys[i] = keyOf(i) * MAX_N + tiePos[i];
  keys.sort(numAsc);
  var byPos = new Int32Array(n);
  for (var p = 0; p < n; p++) byPos[tiePos[p]] = p;
  var out = new Int32Array(n);
  for (var k = 0; k < n; k++) out[k] = byPos[keys[k] % MAX_N];
  return out;
}

var SORT_KEYS = {
  stars: function (p) { return DESC - (p.stars || 0); },
  trending: function (p) { return DESC - (p.vel30 || 0); },
  "new": function (p) { return DESC - dayKey(p.listed); },
  updated: function (p) { return DESC - dayKey(p.updated); }
};

// The ordering for a sort mode, sorted on first use (ties keep rank order).
export function ordering(idx, plugins, sort) {
  if (!SORT_KEYS[sort] && sort !== "rank") sort = "rank";
  if (idx.order[sort]) return idx.order[sort];
  var n = idx.n;
  if (!idx.order.rank) {
    var ident = new Array(n);
    for (var k = 0; k < n; k++) ident[k] = k;
    idx.order.rank = orderBy(n, function (x) { return plugins[x].rank || 1e6; }, ident);
    var pos = new Array(n);
    for (var r = 0; r < n; r++) pos[idx.order.rank[r]] = r;
    idx.rankPos = pos;
  }
  if (sort !== "rank") {
    var key = SORT_KEYS[sort];
    idx.order[sort] = orderBy(n, function (x) { return key(plugins[x]); }, idx.rankPos);
  }
  return idx.order[sort];
}

// plugins: model objects from data.mjs (fields: id name author tags desc rank stars vel30
// listed updated). Returns the index; plugins are not mutated.
export function buildIndex(plugins) {
  var n = plugins.length;
  if (n >= MAX_N) throw new Error("search index supports < " + MAX_N + " plugins");
  var raw = new Array(n);
  var text = new Array(n);
  for (var i = 0; i < n; i++) {
    var p = plugins[i];
    raw[i] = oneLine(p.name) + "\n" + oneLine(p.author) + "\n" + oneLine((p.tags || []).join(" "));
    text[i] = oneLine(p.id) + " " + oneLine(p.desc);
  }
  // One normalize over all short fields instead of three per plugin. id + description are
  // only lowercased and accent-folded: query words never contain punctuation, so a word
  // still matches inside "bar," and the 1 MB punctuation pass is skipped (cold start).
  var short = normalizeBlock(raw.join("\n")).split("\n");
  var long = text.join("\n").replace(ACCENTED, fold).toLowerCase().split("\n");
  var idx = {
    n: n, nl: new Array(n), hay: new Array(n), nEnd: new Int32Array(n), aEnd: new Int32Array(n), tEnd: new Int32Array(n),
    nameChars: new Int32Array(n), order: {}, rankPos: null, cache: {}, cacheSize: 0
  };
  for (var j = 0; j < n; j++) {
    var nm = short[j * 3].trim();
    var au = short[j * 3 + 1].trim();
    var tg = short[j * 3 + 2].trim();
    idx.nl[j] = nm;
    idx.hay[j] = nm + " " + au + " " + tg + " " + long[j];
    idx.nEnd[j] = nm.length;
    idx.aEnd[j] = nm.length + 1 + au.length;
    idx.tEnd[j] = idx.aEnd[j] + 1 + tg.length;
    idx.nameChars[j] = charMask(nm);
  }
  ordering(idx, plugins, "rank");
  return idx;
}

// Is `w` a subsequence of `s`? ("ytdlp" -> "yt dlp")
export function fuzzy(s, w) {
  var j = 0;
  for (var i = 0; i < s.length && j < w.length; i++)
    if (s.charCodeAt(i) === w.charCodeAt(j)) j++;
  return j === w.length;
}

// Best location score of word w (chars = charMask(w)) in plugin i (0 = no match).
export function wordScore(idx, i, w, chars) {
  var h = idx.hay[i];
  var pos = h.indexOf(w);
  if (pos === -1) return w.length >= 2 && (idx.nameChars[i] & chars) === chars && fuzzy(idx.nl[i], w) ? PTS.fuzzy : 0;
  if (pos < idx.nEnd[i]) {
    if (pos === 0 || h.charCodeAt(pos - 1) === 32) return PTS.namePrefix;
    return idx.nl[i].indexOf(" " + w) !== -1 ? PTS.namePrefix : PTS.name;
  }
  if (pos < idx.aEnd[i]) return PTS.author;
  if (pos < idx.tEnd[i]) return PTS.tag;
  return PTS.text;
}

export function filterKey(f, sort) {
  f = f || {};
  return [sort, f.cat || "all", f.kind || "all", f.verdict || "all", f.inst ? "1" : "0", f.instVersion || 0].join("|");
}

export function passes(p, f, installed) {
  if (f.cat && f.cat !== "all" && p.cat !== f.cat) return false;
  if (f.kind && f.kind !== "all" && p.kind !== f.kind) return false;
  if (f.verdict && f.verdict !== "all" && p.verdict !== f.verdict) return false;
  if (f.inst && !(installed && installed[p.id])) return false;
  return true;
}

// Can the previous result set seed this query? Only when every previous word is a
// prefix of the word at the same position (typing forward / adding words).
export function narrows(prevWords, ws) {
  if (!prevWords || prevWords.length > ws.length) return false;
  for (var i = 0; i < prevWords.length; i++)
    if (ws[i].indexOf(prevWords[i]) !== 0) return false;
  return true;
}

// query: raw text; f: {cat, kind, verdict, inst, instVersion}; installed: {id: true};
// prev: the previous return value (optional). Returns {res: Int32Array of plugin indices
// best-first, count, matched: Int32Array of positions in the ordering, words, key, scores}.
export function search(idx, plugins, query, f, sort, installed, prev) {
  f = f || {};
  var order = ordering(idx, plugins, sort);
  sort = idx.order[sort] ? sort : "rank";
  var ws = words(query);
  var nw = ws.length;
  var key = filterKey(f, sort);
  var anyF = (f.cat && f.cat !== "all") || (f.kind && f.kind !== "all") || (f.verdict && f.verdict !== "all") || f.inst;
  var seeded = !!(prev && prev.key === key && narrows(prev.words, ws));
  var count = seeded ? prev.count : order.length;
  var seed = seeded ? prev.matched : null;
  // Per word: scores (UNSCORED = not computed yet); unchanged words reuse earlier ones.
  var S = new Array(nw);
  var C = new Array(nw);
  for (var w = 0; w < nw; w++) {
    C[w] = charMask(ws[w]);
    if (idx.cache[ws[w]]) S[w] = idx.cache[ws[w]];
    else if (seeded && w < prev.words.length && prev.words[w] === ws[w]) S[w] = prev.scores[w];
    else S[w] = new Uint8Array(idx.n).fill(UNSCORED);
  }
  // The first word is scored for every candidate of an unfiltered, unseeded walk: complete.
  var complete = nw > 0 && !seeded && !anyF && !idx.cache[ws[0]];
  var exact = nw ? ws.join(" ") : null;
  var matched = new Int32Array(count);
  var slots = nw ? new Uint8Array(count) : null;
  var tally = new Int32Array(BUCKETS);
  var m = 0;
  for (var c = 0; c < count; c++) {
    var pos = seeded ? seed[c] : c;
    var i = order[pos];
    if (anyF && !passes(plugins[i], f, installed)) continue;
    var sc = 0;
    for (var k = 0; k < nw; k++) {
      var v = S[k][i];
      if (v === UNSCORED) {
        v = wordScore(idx, i, ws[k], C[k]);
        S[k][i] = v;
      }
      if (v === 0) {
        sc = -1;
        break;
      }
      sc += v;
    }
    if (sc < 0) continue;
    matched[m] = pos;
    if (nw) {
      if (idx.nl[i] === exact) sc += PTS.exact;
      var slot = sc >= BUCKETS ? BUCKETS - 1 : sc;
      slots[m] = slot;
      tally[slot]++;
    }
    m++;
  }
  var res = new Int32Array(m);
  if (!nw) {
    for (var e = 0; e < m; e++) res[e] = order[matched[e]];
  } else {
    // Counting sort, highest bucket first; stable, so ties keep the ordering.
    var start = new Int32Array(BUCKETS);
    var acc = 0;
    for (var s = BUCKETS - 1; s >= 0; s--) {
      start[s] = acc;
      acc += tally[s];
    }
    for (var r = 0; r < m; r++) res[start[slots[r]]++] = order[matched[r]];
  }
  if (complete) remember(idx, ws[0], S[0]);
  return { res: res, count: m, matched: matched.subarray(0, m), words: ws, key: key, scores: S };
}

// Complete per-word score arrays, shared by all later queries (bounded).
function remember(idx, w, scores) {
  if (idx.cacheSize >= CACHE_MAX) {
    var keep = {};
    for (var k in idx.cache) if (k.length === 1) keep[k] = idx.cache[k];
    idx.cache = keep;
    idx.cacheSize = Object.keys(keep).length;
  }
  idx.cache[w] = scores;
  idx.cacheSize++;
}

// Scores every single-character word once (the first keystroke is the most expensive
// one). The store's worker runs this right after the index; the benchmark does the same.
export function warm(idx, plugins) {
  var chars = "abcdefghijklmnopqrstuvwxyz0123456789";
  for (var i = 0; i < chars.length; i++)
    if (!idx.cache[chars.charAt(i)]) search(idx, plugins, chars.charAt(i), {}, "rank", {}, null);
}

// Replays typing `phrases` letter by letter (each keystroke narrows from the previous one,
// as the store does); returns per-keystroke milliseconds measured with `now`
// (performance.now in Node, Date.now in QML, where `reps` > 1 averages out the 1 ms clock).
export function benchKeystrokes(idx, plugins, phrases, now, reps) {
  reps = reps || 1;
  var times = [];
  for (var p = 0; p < phrases.length; p++) {
    var prev = null;
    for (var k = 1; k <= phrases[p].length; k++) {
      var q = phrases[p].slice(0, k);
      var t0 = now();
      var out = null;
      for (var r = 0; r < reps; r++) out = search(idx, plugins, q, {}, "rank", {}, prev);
      times.push((now() - t0) / reps);
      prev = out;
    }
  }
  return times;
}

export function percentile(values, p) {
  if (!values.length) return 0;
  var v = Array.prototype.slice.call(values).sort(numAsc);
  return v[Math.min(v.length - 1, Math.floor((p / 100) * v.length))];
}
