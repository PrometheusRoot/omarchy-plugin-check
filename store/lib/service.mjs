// The store's data service: owns the search columns and the search index and answers the
// UI's messages. It runs inside the WorkerScript (ui/worker.mjs, ADR-0031) so parsing the
// 1.6 MB search file or a slow keystroke never blocks a frame; node tests drive it directly.
// The home slice is mapped on the GUI thread (lib/data.mjs fromHome) and never comes here
// (ADR-0032). Messages and replies are plain JSON-able objects (WorkerScript copies them).
import * as Data from "./data.mjs";
import * as Search from "./search.mjs";

export var PAGE = 60;

export function createService() {
  return { t: null, idx: null, last: null, shelves: {} };
}

function rows(svc, list, limit, from) {
  var out = [];
  for (var i = from || 0; i < list.length && out.length < limit; i++) out.push(Data.record(svc.t, list[i]));
  return out;
}

function now() {
  return Date.now();
}

function index(svc) {
  if (!svc.idx) svc.idx = Search.buildIndex(svc.t);
  return svc.idx;
}

export function handle(svc, msg) {
  var t0 = now();
  switch (msg.type) {
    case "load": {
      // msg.text: store-search.json; msg.imageBase from the home slice; msg.byCategory:
      // {cat: [ids]} (home shelves, for "similar").
      var doc = JSON.parse(msg.text);
      var t1 = now();
      svc.t = Data.fromSearch(doc, msg.imageBase);
      svc.shelves = msg.byCategory || {};
      svc.idx = null;
      svc.last = null;
      return { type: "loaded", total: svc.t.n, ms: { parse: t1 - t0, map: now() - t1 } };
    }
    case "index": {
      // Searchable from here; single characters are pre-scored afterwards in "warm" chunks.
      index(svc);
      return { type: "indexed", ms: { index: now() - t0 } };
    }
    case "warm": {
      var from = msg.from || 0;
      var chars = Search.WARM_CHARS.slice(from, from + (msg.count || 4));
      Search.warm(index(svc), chars);
      var next = from + chars.length;
      return { type: "warmed", next: next < Search.WARM_CHARS.length ? next : -1, ms: now() - t0 };
    }
    case "search": {
      var installed = msg.installed || {};
      var r = Search.search(index(svc), msg.q || "", msg.f || {}, msg.sort || "rank", installed, svc.last);
      svc.last = r;
      var ms = now() - t0;
      return { type: "results", seq: msg.seq, q: msg.q, count: r.count, words: r.words, ms: ms, rows: rows(svc, r.res, msg.limit || PAGE) };
    }
    case "page": {
      var res = svc.last ? svc.last.res : [];
      return { type: "page", seq: msg.seq, offset: msg.offset, rows: rows(svc, res, msg.limit || PAGE, msg.offset) };
    }
    case "records": {
      var list = [];
      for (var j = 0; j < (msg.ids || []).length; j++) {
        var ix = svc.t.byId[msg.ids[j]];
        if (ix !== undefined) list.push(Data.record(svc.t, ix));
      }
      return { type: "records", tag: msg.tag, rows: list };
    }
    case "browse": {
      // Category grid: top by rank, blocked hidden (approval note), optional kind filter.
      var order = Search.ordering(index(svc), "rank");
      var t = svc.t;
      var got = [];
      for (var o = 0; o < order.length && got.length < (msg.limit || 30); o++) {
        var i = order[o];
        if (t.cat[i] !== msg.cat || t.verdict[i] === "blocked") continue;
        if (msg.kind && msg.kind !== "all" && t.kind[i] !== msg.kind) continue;
        got.push(Data.record(t, i));
      }
      return { type: "browse", cat: msg.cat, kind: msg.kind, rows: got };
    }
    case "similar": {
      var me = svc.t.byId[msg.id];
      var cat = me === undefined ? "" : svc.t.cat[me];
      var top = svc.shelves[cat] || [];
      var sim = [];
      for (var s = 0; s < top.length && sim.length < 4; s++) {
        var k = svc.t.byId[top[s]];
        if (k !== undefined && k !== me && svc.t.verdict[k] !== "blocked") sim.push(Data.record(svc.t, k));
      }
      return { type: "similar", id: msg.id, rows: sim };
    }
    case "bench": {
      var times = Search.benchKeystrokes(index(svc), msg.phrases, now, msg.reps || 5);
      return { type: "bench", n: times.length, p50: Search.percentile(times, 50), p95: Search.percentile(times, 95), p99: Search.percentile(times, 99) };
    }
    default:
      return { type: "error", error: "unknown message " + msg.type };
  }
}
