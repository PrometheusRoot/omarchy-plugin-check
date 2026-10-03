// Panel + bar widget logic: status.json -> rows, worst state, shield tint, snapshot badge,
// and the argv the QML hands to processes. Pure (no Qt types, no I/O); node --test covers it.
// Anything that becomes a process argument is validated here (docs/ENGINEERING.md).

// Nerd Font (Material Design) codepoints, the same as lib/tty.jq and store/lib/format.mjs.
export var ICON = {
  shield: "\u{f0499}", safe: "\u{f0cc8}", caution: "\u{f0ecd}", risky: "\u{f0238}", blocked: "\u{f073a}",
  unreviewed: "\u{f0625}", stale: "\u{f0150}", retired: "\u{f003c}", unlisted: "\u{f0337}",
  commit: "\u{f0718}", tree: "\u{f0645}", snap: "\u{f120e}", rescan: "\u{f0450}", ext: "\u{f03cc}",
  remove: "\u{f0156}", check: "\u{f012c}", cross: "\u{f0156}", store: "\u{f04dc}"
};

// Worst last; the same order as lib/opc.jq `states`.
export var ORDER = ["safe", "caution", "unreviewed", "unlisted", "stale", "retired", "risky", "blocked"];

// state -> palette token (resolved by palette()).
export var COLOR = {
  safe: "green", caution: "yellow", risky: "orange", blocked: "red",
  stale: "blue", unreviewed: "muted", unlisted: "muted", retired: "muted"
};

export var DESCRIBE = {
  safe: "all installed plugins reviewed safe",
  caution: "at least one caution, none worse",
  risky: "at least one risky plugin",
  blocked: "a blocked plugin is installed",
  unreviewed: "a plugin has no report from any trusted provider",
  stale: "installed commit and tree differ from the reviewed ones",
  unlisted: "installed from a url that is not on plugins.omarchy.org",
  retired: "removed from the marketplace; no verdict is computed"
};

export var PLUGIN_ID = "io.github.prometheusroot.omarchy-store";
export var APP = "omarchy-store";
// The project page until the P4 site is live.
export var SITE = "https://github.com/PrometheusRoot/omarchy-plugin-check";
var ID_RE = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
var PATH_RE = /^\/[A-Za-z0-9_./-]+$/;

export function rank(state) {
  var i = ORDER.indexOf(state);
  return i < 0 ? ORDER.indexOf("unreviewed") : i;
}

export function sha7(s) {
  return typeof s === "string" && s.length >= 7 ? s.slice(0, 7) : "—";
}

export function isId(id) {
  return typeof id === "string" && ID_RE.test(id) && id.indexOf("..") < 0;
}

// status.json text -> {doc, error}. Anything that is not our document is an error.
export function parseStatus(text) {
  if (!text) return { doc: null, error: "no status yet" };
  try {
    var doc = JSON.parse(text);
    if (!doc || doc.kind !== "omarchy-plugin-check/status" || !Array.isArray(doc.plugins))
      return { doc: null, error: "not a status document" };
    return { doc: doc, error: "" };
  } catch (e) {
    return { doc: null, error: "unreadable status.json" };
  }
}

// {state, count}: the worst state and how many plugins share it; state null = nothing installed.
export function worst(doc) {
  var ps = doc && Array.isArray(doc.plugins) ? doc.plugins : [];
  var w = null;
  var n = 0;
  for (var i = 0; i < ps.length; i++) {
    var s = ORDER.indexOf(ps[i].state) < 0 ? "unreviewed" : ps[i].state;
    if (w === null || rank(s) > rank(w)) {
      w = s;
      n = 1;
    } else if (s === w) n++;
  }
  return { state: w, count: n };
}

// Bar label: shield + count (no count when everything is safe or nothing is installed).
export function shieldLabel(w) {
  if (!w || w.state === null || w.state === "safe") return ICON.shield;
  return ICON.shield + " " + w.count;
}

export function shieldTip(w, doc) {
  var hint = "\nclick: store · right click: verdicts · middle click: rescan";
  if (!w || w.state === null) return APP + " · no third-party plugins" + hint;
  var snap = doc && doc.snapshot && doc.snapshot.ok ? "" : " · no verified snapshot";
  return APP + " · worst: " + w.state + " (" + w.count + ")" + snap + hint;
}

function eqOf(v) {
  return v === true ? "=" : v === false ? "≠" : "—";
}

// One panel row per installed plugin, worst first (the CLI already sorts; keep it stable).
export function rows(doc) {
  var ps = doc && Array.isArray(doc.plugins) ? doc.plugins.slice() : [];
  ps.sort(function (a, b) { return rank(b.state) - rank(a.state) || String(a.id).localeCompare(String(b.id)); });
  return ps.map(function (p) {
    var state = ORDER.indexOf(p.state) < 0 ? "unreviewed" : p.state;
    var stale = state === "stale" && p.combined && p.reviewed && p.reviewed.commit;
    return {
      id: String(p.id || ""),
      name: String(p.name || p.id || ""),
      sub: String(p.id || "") + " · " + sha7(p.head),
      state: state,
      icon: ICON[state],
      color: COLOR[state],
      chip: stale ? p.combined + "@" + sha7(p.reviewed.commit) : state,
      chipColor: stale ? COLOR[p.combined] || "muted" : COLOR[state],
      commitEq: eqOf(p.commitMatch),
      treeEq: eqOf(p.treeMatch),
      hasMatch: p.commitMatch === true || p.commitMatch === false,
      removable: state === "blocked" || state === "retired",
      note: p.note || "",
      url: typeof p.url === "string" && p.url.indexOf("https://plugins.omarchy.org/") === 0 ? p.url : ""
    };
  });
}

// "45s" | "12m" | "5h" | "3d"
export function age(sec) {
  if (sec === null || sec === undefined || !isFinite(sec) || sec < 0) return "?";
  if (sec < 60) return Math.floor(sec) + "s";
  if (sec < 3600) return Math.floor(sec / 60) + "m";
  if (sec < 172800) return Math.floor(sec / 3600) + "h";
  return Math.floor(sec / 86400) + "d";
}

export function snapshotBadge(doc, nowSec) {
  var s = doc && doc.snapshot;
  if (!s || !s.ok) {
    return { ok: false, text: "snapshot ✗", tip: (s && s.error) || "no verified snapshot: run omarchy-plugin-check update" };
  }
  var gen = Date.parse(s.generatedAt) / 1000;
  var a = age(nowSec - gen);
  var provs = (s.providers || []).map(function (p) { return p.id + " " + p.tier; }).join(", ");
  return {
    ok: true,
    text: "snapshot ✓ · " + a,
    tip: "signed snapshot verified (ssh-keygen -Y)" + (s.dev ? " · dev key" : "") + "\nversion " + s.version
      + " · " + a + " old" + (provs ? "\nproviders " + provs : "")
  };
}

// The CLI the panel runs: the copy shipped next to it (no PATH or setup needed).
export function cliPath(pluginDirUrl) {
  var p = String(pluginDirUrl || "").replace(/^file:\/\//, "").replace(/\/+$/, "");
  var bin = p + "/bin/omarchy-plugin-check";
  return PATH_RE.test(bin) ? bin : "";
}

// The store app shipped in the same repository (store/ next to bin/, ADR-0042). Its launcher
// is single-instance: a second click focuses the open window.
export function storeArgv(pluginDirUrl) {
  var p = String(pluginDirUrl || "").replace(/^file:\/\//, "").replace(/\/+$/, "");
  var bin = p + "/store/bin/omarchy-store";
  return PATH_RE.test(bin) ? [bin] : null;
}

export function rescanArgv(bin) {
  return bin ? [bin, "status", "--json"] : null;
}

// omarchy-launch-floating-terminal-with-presentation runs its arguments through `bash -c`,
// so only validated ids and paths may reach it.
export function cardArgv(bin, id) {
  if (!bin || !PATH_RE.test(bin) || !isId(id)) return null;
  return ["omarchy-launch-floating-terminal-with-presentation", bin + " " + id];
}

export function removeArgv(id) {
  if (!isId(id)) return null;
  return ["omarchy-launch-floating-terminal-with-presentation", "omarchy plugin remove " + id];
}

export function openArgv(url) {
  if (typeof url !== "string" || !/^https:\/\/[A-Za-z0-9.-]+\/[A-Za-z0-9._~:/?#@!$&'()*+,;=%-]*$/.test(url)) return null;
  return ["xdg-open", url];
}

// ---- theme: ~/.local/state/omarchy/current/theme/colors.toml -> state palette

export function parseColors(raw) {
  var out = {};
  var lines = String(raw || "").split("\n");
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})["']?\s*(#.*)?$/);
    if (m) out[m[1]] = m[2];
  }
  return out;
}

function first(c, keys, fallback) {
  for (var i = 0; i < keys.length; i++) if (c[keys[i]]) return c[keys[i]];
  return fallback;
}

// Tokyo Night fallbacks (the mockup's default skin) for anything a theme omits.
export function palette(raw) {
  var c = parseColors(raw);
  var fg = first(c, ["foreground", "color7"], "#a9b1d6");
  var yellow = first(c, ["yellow", "color3"], "#e0af68");
  return {
    fg: fg,
    bg: first(c, ["background", "color0"], "#1a1b26"),
    muted: first(c, ["muted", "color8"], "#565f89"),
    green: first(c, ["green", "color2"], "#9ece6a"),
    yellow: yellow,
    orange: first(c, ["orange", "bright_yellow", "color11"], "#ff9e64"),
    red: first(c, ["red", "color1"], "#f7768e"),
    blue: first(c, ["blue", "color4"], "#7aa2f7")
  };
}

export function tint(pal, token) {
  return (pal && pal[token]) || (pal && pal.fg) || "#a9b1d6";
}
