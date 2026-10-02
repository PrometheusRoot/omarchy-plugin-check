// Omarchy theme (colors.toml) -> the store's design tokens. Pure; Theme.qml reads the file.
// Token names follow the approved mockup (--bg, --surface, --border-strong, ...).

export function parseColors(raw) {
  var out = {};
  var lines = String(raw || "").split("\n");
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?([^"'#\s][^"']*|#[0-9A-Fa-f]{3,8})["']?\s*(#.*)?$/);
    if (m) out[m[1]] = m[2].trim();
  }
  return out;
}

export function isHex(c) {
  return typeof c === "string" && /^#[0-9A-Fa-f]{6}$/.test(c);
}

export function rgb(hex) {
  return [parseInt(hex.slice(1, 3), 16), parseInt(hex.slice(3, 5), 16), parseInt(hex.slice(5, 7), 16)];
}

export function hex2(n) {
  var s = Math.max(0, Math.min(255, Math.round(n))).toString(16);
  return s.length < 2 ? "0" + s : s;
}

// a + (b - a) * t, per channel.
export function mix(a, b, t) {
  var x = rgb(a);
  var y = rgb(b);
  return "#" + hex2(x[0] + (y[0] - x[0]) * t) + hex2(x[1] + (y[1] - x[1]) * t) + hex2(x[2] + (y[2] - x[2]) * t);
}

export function luminance(hex) {
  var c = rgb(hex);
  return (0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]) / 255;
}

export function first(c) {
  for (var i = 1; i < arguments.length; i++)
    if (isHex(c[arguments[i]])) return c[arguments[i]];
  return null;
}

// Tokyo Night defaults = the mockup's default skin; used for anything a theme omits.
export var DEFAULT = {
  background: "#1a1b26", dark_background: "#13141c", lighter_background: "#24283b", muted: "#414868",
  foreground: "#a9b1d6", bright_foreground: "#c0caf5", red: "#f7768e", yellow: "#e0af68", green: "#9ece6a",
  blue: "#7aa2f7", orange: "#ff9e64", magenta: "#bb9af7", cyan: "#7dcfff"
};

export function tokens(c, name) {
  c = c || {};
  var bg = first(c, "background", "color0") || DEFAULT.background;
  var fg = first(c, "foreground", "color7") || DEFAULT.foreground;
  var light = c.mode === "light" || (c.mode !== "dark" && luminance(bg) > 0.5);
  var lighter = first(c, "lighter_background", "selection", "color8") || mix(bg, fg, 0.1);
  var t = {
    name: name || "",
    light: light,
    bg: bg,
    bgDeep: first(c, "dark_background") || mix(bg, light ? "#ffffff" : "#000000", 0.25),
    surface2: lighter,
    surface: mix(bg, lighter, 0.5),
    borderSubtle: lighter,
    borderStrong: first(c, "muted", "color8") || mix(bg, fg, 0.3),
    text: first(c, "bright_foreground", "light_foreground", "color15") || fg,
    textSecondary: fg,
    muted: mix(fg, bg, 0.22),
    red: first(c, "red", "color1") || DEFAULT.red,
    green: first(c, "green", "color2") || DEFAULT.green,
    yellow: first(c, "yellow", "color3") || DEFAULT.yellow,
    blue: first(c, "blue", "color4") || DEFAULT.blue,
    purple: first(c, "bright_magenta", "magenta", "color5") || DEFAULT.magenta,
    cyan: first(c, "cyan", "color6") || DEFAULT.cyan
  };
  t.orange = first(c, "orange", "bright_yellow") || t.yellow;
  t.brand = t.green;
  t.mark = mix(t.bg, t.yellow, 0.35);
  t.scrim = t.bgDeep;
  return t;
}

// Next theme name in a sorted list (dev-only `t`).
export function nextTheme(names, current) {
  if (!names.length) return current;
  var i = names.indexOf(current);
  return names[(i + 1) % names.length];
}
