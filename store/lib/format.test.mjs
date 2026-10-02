import assert from "node:assert/strict";
import { test } from "node:test";
import * as F from "./format.mjs";

test("every outcome maps to a glyph and a theme colour token", () => {
  for (const o of [...F.OUTCOMES, "stale"]) {
    assert.ok(F.ICON[F.outcome(o).icon], o);
    assert.ok(["green", "yellow", "orange", "red", "muted", "blue"].includes(F.outcome(o).color), o);
  }
  assert.deepEqual(F.outcome("bogus"), F.outcome("unreviewed"));
  assert.equal(F.outcome("blocked").color, "red");
  assert.equal(F.outcome("risky").color, "orange");
});

test("every icon the UI names exists", () => {
  for (const [, icon] of F.CATEGORIES) assert.ok(F.ICON[icon], icon);
  for (const [, icon] of F.CAPS) assert.ok(F.ICON[icon], icon);
  for (const v of Object.values(F.ICON)) assert.equal([...v].length, 1);
});

test("criteria vocabulary matches the spec and has short labels", () => {
  assert.equal(F.CRITERIA.length, 8);
  for (const c of F.CRITERIA) assert.ok(F.CRITERIA_SHORT[c]);
  assert.equal(F.CRITERIA_SHORT["no-network"], "no-net");
});

test("int is locale independent", () => {
  assert.equal(F.int(4523), "4,523");
  assert.equal(F.int(1234567), "1,234,567");
  assert.equal(F.int(12), "12");
  assert.equal(F.int(-1500), "-1,500");
  assert.equal(F.int(null), "—");
});

test("ago buckets like the mockup", () => {
  const now = Date.parse("2026-10-01T12:00:00Z");
  assert.equal(F.ago("2026-10-01T06:00:00Z", now), "today");
  assert.equal(F.ago("2026-09-30T12:00:00Z", now), "1d");
  assert.equal(F.ago("2026-09-21T12:00:00Z", now), "10d");
  assert.equal(F.ago("2026-06-01", now), "4mo");
  assert.equal(F.ago("2024-09-01", now), "2y");
  assert.equal(F.ago("", now), "—");
  assert.equal(F.ago("not a date", now), "—");
});

test("small formatters", () => {
  assert.equal(F.shortSha("26b1fa823756f164b472c7eab0d22f102044dc35"), "26b1fa8");
  assert.equal(F.shortSha(null), "—");
  assert.equal(F.hours(5), "5h");
  assert.equal(F.hours(72), "3d");
  assert.equal(F.hours(null), "—");
  assert.equal(F.kb(2048), "2 KB");
  assert.equal(F.kb(3 * 1048576), "3.0 MB");
  assert.equal(F.ms(0.256), "0.26");
  assert.equal(F.ms(12.34), "12.3");
  assert.equal(F.dateOnly("2026-09-30T14:53:56Z"), "2026-09-30");
  assert.equal(F.clampText("abcdef", 4), "abc…");
  assert.equal(F.capLevel("med"), "med");
  assert.equal(F.capLevel(undefined), "none");
  assert.equal(F.sevOutcome("critical"), "blocked");
  assert.equal(F.sevOutcome("low"), "");
});

test("initials and accent tiles", () => {
  assert.equal(F.initials("LetsFG Flights"), "LF");
  assert.equal(F.initials("yt-dlp"), "YD");
  assert.equal(F.initials("omamail"), "OM");
  assert.equal(F.accentFor("x", "violet"), "purple");
  assert.equal(F.accentFor("same-id", ""), F.accentFor("same-id", ""));
  assert.ok(["cyan", "green", "red", "yellow", "orange", "purple"].includes(F.accentFor("anything", "")));
});

test("highlight escapes markup and marks every match, case-insensitively", () => {
  const h = F.highlight("Weather <b>weather</b>", ["weather"], "#333");
  assert.equal((h.match(/<span/g) || []).length, 2);
  assert.ok(h.includes("&lt;b&gt;"));
  assert.ok(!h.includes("<b>"));
  assert.equal(F.highlight("a&b", [], "#000"), "a&amp;b");
  // overlapping words never produce nested or broken markup
  const o = F.highlight("weather", ["wea", "eat"], "#000");
  assert.equal((o.match(/<span/g) || []).length, (o.match(/<\/span>/g) || []).length);
  assert.equal(o.replace(/<[^>]+>/g, ""), "weather");
});
