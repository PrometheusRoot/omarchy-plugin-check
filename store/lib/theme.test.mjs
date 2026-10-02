import assert from "node:assert/strict";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { test } from "node:test";
import * as T from "./theme.mjs";

const TOKYO = `mode = "dark"
accent = "#7aa2f7"
muted = "#414868"
background = "#1a1b26"
dark_background = "#13141c"
lighter_background = "#24283b"
foreground = "#a9b1d6"
bright_foreground = "#c0caf5"
red = "#f7768e"
yellow = "#e0af68"
orange = "#eb927b"
green = "#9ece6a"
cyan = "#449dab"
blue = "#7aa2f7"
magenta = "#ad8ee6"
bright_magenta = "#bb9af7"
`;

const KEYS = ["bg", "bgDeep", "surface", "surface2", "borderSubtle", "borderStrong", "text", "textSecondary", "muted", "brand", "red", "yellow", "green", "blue", "orange", "purple", "cyan", "mark"];

test("parseColors reads key = \"#hex\" lines and ignores comments", () => {
  const c = T.parseColors(`# comment\nbackground = "#101010" # trailing\nmode = "dark"\nbad line\n`);
  assert.equal(c.background, "#101010");
  assert.equal(c.mode, "dark");
  assert.equal(Object.keys(c).length, 2);
});

test("tokyo night maps onto the mockup's tokens", () => {
  const t = T.tokens(T.parseColors(TOKYO), "tokyo-night");
  assert.equal(t.bg, "#1a1b26");
  assert.equal(t.bgDeep, "#13141c");
  assert.equal(t.surface2, "#24283b");
  assert.equal(t.borderStrong, "#414868");
  assert.equal(t.text, "#c0caf5");
  assert.equal(t.textSecondary, "#a9b1d6");
  assert.equal(t.brand, t.green);
  assert.equal(t.purple, "#bb9af7");
  assert.equal(t.light, false);
  // surface sits between background and lighter_background
  assert.equal(t.surface, T.mix("#1a1b26", "#24283b", 0.5));
});

test("a sparse or legacy theme falls back to colorN and defaults", () => {
  const t = T.tokens(T.parseColors(`color0 = "#ffffff"\ncolor7 = "#000000"\ncolor1 = "#aa0000"`), "legacy");
  assert.equal(t.bg, "#ffffff");
  assert.equal(t.red, "#aa0000");
  assert.equal(t.light, true);
  for (const k of KEYS) assert.match(t[k], /^#[0-9a-f]{6}$/i, k);
  assert.equal(t.orange, t.yellow);
});

test("every installed Omarchy theme yields a full token set", { skip: !existsSync("/usr/share/omarchy/themes") }, () => {
  for (const name of readdirSync("/usr/share/omarchy/themes")) {
    const f = `/usr/share/omarchy/themes/${name}/colors.toml`;
    if (!existsSync(f)) continue;
    const t = T.tokens(T.parseColors(readFileSync(f, "utf8")), name);
    for (const k of KEYS) assert.match(t[k], /^#[0-9a-f]{6}$/i, `${name}.${k}`);
  }
});

test("mix and nextTheme", () => {
  assert.equal(T.mix("#000000", "#ffffff", 0.5), "#808080");
  assert.equal(T.mix("#102030", "#102030", 0.3), "#102030");
  assert.equal(T.nextTheme(["a", "b", "c"], "c"), "a");
  assert.equal(T.nextTheme(["a", "b"], "zzz"), "a");
  assert.equal(T.nextTheme([], "x"), "x");
});
