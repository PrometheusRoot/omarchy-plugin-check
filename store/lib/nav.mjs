// Keyboard map (exactly the mockup's; status tab "keys" box) and grid cursor movement.
// Pure: App.qml turns a QML KeyEvent into {key, text, mods} and dispatches the action.

// Qt::Key values (stable ABI).
export var QT = {
  Escape: 0x01000000, Tab: 0x01000001, Backspace: 0x01000003, Return: 0x01000004, Enter: 0x01000005,
  Left: 0x01000012, Up: 0x01000013, Right: 0x01000014, Down: 0x01000015, PageUp: 0x01000016, PageDown: 0x01000017
};

export var TABS = ["home", "search", "browse", "installed", "status"];
export var SECTIONS = { o: "overview", s: "security", x: "tech", d: "deps", a: "activity" };

export function keyName(code, text) {
  if (code === QT.Escape) return "Escape";
  if (code === QT.Return || code === QT.Enter) return "Enter";
  if (code === QT.Left) return "Left";
  if (code === QT.Right) return "Right";
  if (code === QT.Up) return "Up";
  if (code === QT.Down) return "Down";
  if (code === QT.PageUp) return "PageUp";
  if (code === QT.PageDown) return "PageDown";
  return text || "";
}

// ctx: {inInput, dialog ("" | "confirm" | "refused" | "progress" | "done" | "rank" | "remove"),
//       tab ("home".."status" | "detail"), cursor (bool: a card/row is focused), dev, mods}
export function keyAction(key, ctx) {
  ctx = ctx || {};
  if (key === "Escape") return { action: "back" };
  if (ctx.dialog) {
    if (key === "y" && (ctx.dialog === "confirm" || ctx.dialog === "remove")) return { action: "confirm" };
    if (key === "Enter") return { action: "dialogDefault" };
    return { action: "none" };
  }
  if (ctx.inInput) {
    if (key === "Down" || key === "Enter") return { action: "leaveInput" };
    return { action: "type" };
  }
  if (ctx.mods) return { action: "none" };
  if (key === "/") return { action: "focusSearch" };
  if (key.length === 1 && key >= "1" && key <= "5") return { action: "tab", arg: TABS[Number(key) - 1] };
  if (key === "j" || key === "Down") return { action: "move", arg: "down" };
  if (key === "k" || key === "Up") return { action: "move", arg: "up" };
  if (key === "l" || key === "Right") {
    if (key === "l" && ctx.tab === "home" && !ctx.cursor) return { action: "hero", arg: 1 };
    return { action: "move", arg: "right" };
  }
  if (key === "h" || key === "Left") {
    if (key === "h" && ctx.tab === "home" && !ctx.cursor) return { action: "hero", arg: -1 };
    return { action: "move", arg: "left" };
  }
  if (key === "PageDown") return { action: "page", arg: 1 };
  if (key === "PageUp") return { action: "page", arg: -1 };
  if (key === "Enter") return { action: "open" };
  if (key === "i") return { action: "install" };
  if (key === "?") return { action: "rank" };
  if (key === "t") return ctx.dev ? { action: "theme" } : { action: "none" };
  if (ctx.tab === "detail" && SECTIONS[key]) return { action: "section", arg: SECTIONS[key] };
  if (ctx.tab === "status" && key === "e") return { action: "extras" };
  return { action: "none" };
}

// rows: lengths of each focusable row (0 = skip). cur: {r, c} or null (= nothing focused,
// e.g. the home hero). Returns the new cursor; `up` from the first row returns null when
// allowNull (back to the hero), else stays.
export function move(rows, cur, dir, allowNull) {
  var firstRow = -1;
  for (var i = 0; i < rows.length; i++) if (rows[i] > 0) { firstRow = i; break; }
  if (firstRow < 0) return null;
  if (!cur) return dir === "up" && allowNull ? null : { r: firstRow, c: 0 };
  var r = cur.r;
  var c = cur.c;
  if (dir === "left") return { r: r, c: Math.max(0, c - 1) };
  if (dir === "right") return { r: r, c: Math.min(rows[r] - 1, c + 1) };
  var step = dir === "down" ? 1 : -1;
  for (var n = r + step; n >= 0 && n < rows.length; n += step)
    if (rows[n] > 0) return { r: n, c: Math.min(c, rows[n] - 1) };
  if (dir === "up" && allowNull) return null;
  return { r: r, c: c };
}

// Flat list <-> grid with `cols` columns (browse grid, search list with cols = 1).
export function gridRows(count, cols) {
  var rows = [];
  for (var i = 0; i < count; i += cols) rows.push(Math.min(cols, count - i));
  return rows;
}
