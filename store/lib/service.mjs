// The store's data service: owns the snapshot model and the search index and answers the
// UI's messages. It runs inside the WorkerScript (ui/worker.mjs, ADR-0026) so parsing a
// 5 MB snapshot or a slow keystroke never blocks a frame; node tests drive it directly.
// Messages and replies are plain JSON-able objects (WorkerScript copies them).
import * as Data from "./data.mjs";
import * as Search from "./search.mjs";

export var SHELF_SIZE = 12;
export var PAGE = 60;

export function createService() {
  return { model: null, idx: null, last: null, lastKey: "" };
}

function rows(svc, list, limit) {
  var out = [];
  var plugins = svc.model.plugins;
  for (var i = 0; i < list.length && out.length < limit; i++) out.push(plugins[list[i]]);
  return out;
}

// What the first frame needs: hero, shelves, categories, counts, meta. Small (~70
// records) so the UI can also cache it on disk for the next cold start.
export function homePayload(svc) {
  var m = svc.model;
  var byCat = {};
  for (var c in m.shelves.byCategory) byCat[c] = rows(svc, m.shelves.byCategory[c], SHELF_SIZE);
  var cats = {};
  for (var k = 0; k < m.categories.length; k++) cats[m.categories[k].name] = m.categories[k].count;
  return {
    meta: m.meta,
    counts: m.counts,
    total: m.plugins.length,
    catCounts: cats,
    heroes: rows(svc, m.heroes, 6),
    shelves: {
      top: rows(svc, m.shelves.top, SHELF_SIZE),
      trending: rows(svc, m.shelves.trending, SHELF_SIZE),
      "new": rows(svc, m.shelves["new"], SHELF_SIZE),
      updated: rows(svc, m.shelves.updated, SHELF_SIZE),
      safePicks: rows(svc, m.shelves.safePicks, SHELF_SIZE)
    },
    byCategory: byCat
  };
}

function now() {
  return Date.now();
}

export function handle(svc, msg) {
  var t0 = now();
  switch (msg.type) {
    case "load": {
      var snap = JSON.parse(msg.text);
      var t1 = now();
      svc.model = Data.fromSnapshot(snap);
      svc.idx = null;
      svc.last = null;
      var t2 = now();
      var home = homePayload(svc);
      return { type: "loaded", home: home, ms: { parse: t1 - t0, map: t2 - t1 } };
    }
    case "index": {
      svc.idx = Search.buildIndex(svc.model.plugins);
      var t3 = now();
      Search.warm(svc.idx, svc.model.plugins);
      return { type: "indexed", ms: { index: t3 - t0, warm: now() - t3 } };
    }
    case "search": {
      if (!svc.idx) svc.idx = Search.buildIndex(svc.model.plugins);
      var installed = msg.installed || {};
      var r = Search.search(svc.idx, svc.model.plugins, msg.q || "", msg.f || {}, msg.sort || "rank", installed, svc.last);
      svc.last = r;
      var ms = now() - t0;
      return { type: "results", seq: msg.seq, q: msg.q, count: r.count, words: r.words, ms: ms, rows: rows(svc, r.res, msg.limit || PAGE) };
    }
    case "page": {
      var res = svc.last ? svc.last.res : [];
      var out = [];
      for (var i = msg.offset; i < res.length && out.length < (msg.limit || PAGE); i++) out.push(svc.model.plugins[res[i]]);
      return { type: "page", seq: msg.seq, offset: msg.offset, rows: out };
    }
    case "records": {
      var list = [];
      for (var j = 0; j < (msg.ids || []).length; j++) {
        var ix = svc.model.byId[msg.ids[j]];
        if (ix !== undefined) list.push(svc.model.plugins[ix]);
      }
      return { type: "records", tag: msg.tag, rows: list };
    }
    case "browse": {
      // Category grid: top by rank, blocked hidden (approval note), optional kind filter.
      if (!svc.idx) svc.idx = Search.buildIndex(svc.model.plugins);
      var order = Search.ordering(svc.idx, svc.model.plugins, "rank");
      var got = [];
      for (var o = 0; o < order.length && got.length < (msg.limit || 30); o++) {
        var p = svc.model.plugins[order[o]];
        if (p.cat !== msg.cat || p.verdict === "blocked") continue;
        if (msg.kind && msg.kind !== "all" && p.kind !== msg.kind) continue;
        got.push(p);
      }
      return { type: "browse", cat: msg.cat, kind: msg.kind, rows: got };
    }
    case "similar": {
      var me = svc.model.byId[msg.id];
      var cat = me === undefined ? "" : svc.model.plugins[me].cat;
      var top = svc.model.shelves.byCategory[cat] || [];
      var sim = [];
      for (var s = 0; s < top.length && sim.length < 4; s++) if (top[s] !== me) sim.push(svc.model.plugins[top[s]]);
      return { type: "similar", id: msg.id, rows: sim };
    }
    case "bench": {
      if (!svc.idx) svc.idx = Search.buildIndex(svc.model.plugins);
      var times = Search.benchKeystrokes(svc.idx, svc.model.plugins, msg.phrases, now, msg.reps || 5);
      return { type: "bench", n: times.length, p50: Search.percentile(times, 50), p95: Search.percentile(times, 95), p99: Search.percentile(times, 99) };
    }
    default:
      return { type: "error", error: "unknown message " + msg.type };
  }
}
