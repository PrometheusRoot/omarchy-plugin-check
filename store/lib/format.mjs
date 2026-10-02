// Formatting, outcome glyphs/colours, criteria vocabulary and icon glyphs.
// Pure: no Qt types, no I/O. Tested by format.test.mjs.

// Nerd Font (Material Design) codepoints. The mockup's svg icons map 1:1 onto these.
export var ICON = {
  shield: "\u{f0499}", safe: "\u{f0cc8}", caution: "\u{f0ecd}", risky: "\u{f0238}", blocked: "\u{f073a}",
  unreviewed: "\u{f0625}", stale: "\u{f0150}", pass: "\u{f05e1}", fail: "\u{f05d6}", search: "\u{f0349}",
  star: "\u{f04d2}", home: "\u{f06a1}", grid: "\u{f11d9}", dl: "\u{f01da}", trash: "\u{f0a7a}",
  up: "\u{f0450}", trend: "\u{f0535}", "new": "\u{f0394}", clock: "\u{f0150}", users: "\u{f000f}",
  tag: "\u{f04fc}", cpu: "\u{f061a}", monitor: "\u{f0379}", palette: "\u{f0e0c}", code: "\u{f0174}",
  widget: "\u{f1355}", task: "\u{f0135}", sys: "\u{f08bb}", kids: "\u{f01f5}", dots: "\u{f01d8}",
  exec: "\u{f018d}", net: "\u{f059f}", write: "\u{f11e8}", persist: "\u{f0031}", priv: "\u{f030b}",
  pkg: "\u{f03d6}", bin: "\u{f035b}", clip: "\u{f014c}", cam: "\u{f0d5d}", hypr: "\u{f0a1d}",
  layers: "\u{f09fe}", info: "\u{f02fd}", bot: "\u{f167a}", ext: "\u{f03cc}", check: "\u{f012c}",
  x: "\u{f0156}", alert: "\u{f002a}", sig: "\u{f1740}", unsig: "\u{f076d}", perf: "\u{f04c5}",
  commit: "\u{f0718}", rank: "\u{f0128}", snap: "\u{f120e}", left: "\u{f0141}", right: "\u{f0142}",
  play: "\u{f040a}", img: "\u{f0976}", flag: "\u{f023d}", heart: "\u{f02d5}", eye: "\u{f06d0}",
  copy: "\u{f018f}", noimg: "\u{f11d1}", keys: "\u{f097b}", rollback: "\u{f099b}", lock: "\u{f0341}"
};

// outcome -> glyph + theme colour token (Theme.qml resolves the token).
export var OUTCOME = {
  safe: { icon: "safe", color: "green" },
  caution: { icon: "caution", color: "yellow" },
  risky: { icon: "risky", color: "orange" },
  blocked: { icon: "blocked", color: "red" },
  unreviewed: { icon: "unreviewed", color: "muted" },
  stale: { icon: "stale", color: "blue" }
};
export var OUTCOMES = ["safe", "caution", "risky", "blocked", "unreviewed"];

// Criteria vocabulary (spec common.schema.json) with the mockup's short chip labels.
export var CRITERIA = ["safe-to-run", "no-network", "no-exec", "no-persistence", "no-privilege", "no-obfuscation", "no-secrets", "reviewed-by-human"];
export var CRITERIA_SHORT = {
  "safe-to-run": "safe-to-run", "no-network": "no-net", "no-exec": "no-exec", "no-persistence": "no-persist",
  "no-privilege": "no-priv", "no-obfuscation": "no-obfusc", "no-secrets": "no-secrets", "reviewed-by-human": "human"
};

// Capability tiles on the tech tab: [report key, icon, label].
export var CAPS = [
  ["processExec", "exec", "process exec"], ["network", "net", "network"], ["fileWrite", "write", "writes outside plugin"],
  ["persistence", "persist", "persistence"], ["privilege", "priv", "privilege"], ["packageInstall", "pkg", "package install"],
  ["bundledBinary", "bin", "bundled binary"], ["clipboard", "clip", "clipboard"], ["screenCapture", "cam", "screen capture"],
  ["hyprlandIpc", "hypr", "hyprland ipc"]
];

export var CATEGORIES = [
  ["Widgets", "widget"], ["Productivity", "task"], ["System", "sys"], ["Hardware", "cpu"], ["Desktop", "monitor"],
  ["Appearance", "palette"], ["Developer Tools", "code"], ["Kids", "kids"], ["Other", "dots"]
];
export var KINDS = ["Bar widget", "Overlay", "Service", "Panel", "Bar"];
export var ACCENTS = ["cyan", "lime", "rose", "amber", "coral", "violet"];
export var ACCENT_COLOR = { cyan: "cyan", lime: "green", rose: "red", amber: "yellow", coral: "orange", violet: "purple" };

export function outcome(o) {
  return OUTCOME[o] || OUTCOME.unreviewed;
}

export function glyph(o) {
  return ICON[outcome(o).icon];
}

export function categoryIcon(cat) {
  for (var i = 0; i < CATEGORIES.length; i++)
    if (CATEGORIES[i][0] === cat) return ICON[CATEGORIES[i][1]];
  return ICON.dots;
}

// 4523 -> "4,523" (locale-independent; QV4's toLocaleString varies by system locale).
export function int(n) {
  if (n === null || n === undefined || !isFinite(n)) return "—";
  var s = String(Math.round(Math.abs(n)));
  var out = "";
  while (s.length > 3) {
    out = "," + s.slice(-3) + out;
    s = s.slice(0, -3);
  }
  return (n < 0 ? "-" : "") + s + out;
}

export function days(iso, nowMs) {
  if (!iso) return null;
  var t = Date.parse(iso);
  if (!isFinite(t)) return null;
  return Math.max(0, (nowMs - t) / 864e5);
}

// Relative age as in the mockup: today, 1d, 12d, 3mo, 2y.
export function ago(iso, nowMs) {
  var d = days(iso, nowMs);
  if (d === null) return "—";
  d = Math.round(d);
  if (d < 1) return "today";
  if (d === 1) return "1d";
  if (d < 30) return d + "d";
  if (d < 365) return Math.round(d / 30) + "mo";
  return Math.round(d / 365) + "y";
}

export function dateOnly(iso) {
  return iso ? String(iso).slice(0, 10) : "—";
}

export function shortSha(sha) {
  return sha ? String(sha).slice(0, 7) : "—";
}

export function hours(h) {
  if (h === null || h === undefined) return "—";
  return h < 48 ? Math.round(h) + "h" : Math.round(h / 24) + "d";
}

export function kb(bytes) {
  if (!bytes) return "0 KB";
  if (bytes >= 1048576) return (bytes / 1048576).toFixed(1) + " MB";
  return Math.round(bytes / 1024) + " KB";
}

export function ms(v) {
  return v < 1 ? v.toFixed(2) : v.toFixed(1);
}

// Two-letter tile text when the marketplace ships none.
export function initials(name) {
  var words = String(name || "?").replace(/[^A-Za-z0-9 ]+/g, " ").trim().split(/\s+/);
  if (words.length > 1 && words[1]) return (words[0][0] + words[1][0]).toUpperCase();
  return String(words[0] || "?").slice(0, 2).toUpperCase();
}

export function hash32(s) {
  var h = 2166136261;
  s = String(s);
  for (var i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619) >>> 0;
  }
  return h;
}

// Stable tile accent from the id when the snapshot has none.
export function accentFor(id, given) {
  if (given && ACCENT_COLOR[given]) return ACCENT_COLOR[given];
  return ACCENT_COLOR[ACCENTS[hash32(id) % ACCENTS.length]];
}

export function escapeHtml(s) {
  return String(s === null || s === undefined ? "" : s)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

// StyledText with every case-insensitive occurrence of `words` wrapped in a coloured span.
// Matching runs on the raw text so escaping never splits a match.
export function highlight(text, words, color) {
  text = String(text || "");
  if (!words || !words.length) return escapeHtml(text);
  var lower = text.toLowerCase();
  var marks = [];
  for (var w = 0; w < words.length; w++) {
    var word = words[w];
    if (!word) continue;
    var at = lower.indexOf(word);
    while (at !== -1) {
      marks.push([at, at + word.length]);
      at = lower.indexOf(word, at + word.length);
    }
  }
  if (!marks.length) return escapeHtml(text);
  marks.sort(function (a, b) { return a[0] - b[0]; });
  var out = "";
  var pos = 0;
  for (var m = 0; m < marks.length; m++) {
    var s = Math.max(marks[m][0], pos);
    var e = marks[m][1];
    if (e <= pos) continue;
    out += escapeHtml(text.slice(pos, s)) + '<span style="background-color:' + color + '">' + escapeHtml(text.slice(s, e)) + "</span>";
    pos = e;
  }
  return out + escapeHtml(text.slice(pos));
}

// Finding severity -> outcome-family chip colour.
export function sevOutcome(sev) {
  return { critical: "blocked", high: "risky", medium: "caution" }[sev] || "";
}

// Capability level -> tile state.
export function capLevel(l) {
  return l === "low" || l === "med" || l === "high" ? l : "none";
}

export function clampText(s, n) {
  s = String(s || "");
  return s.length > n ? s.slice(0, n - 1) + "…" : s;
}
