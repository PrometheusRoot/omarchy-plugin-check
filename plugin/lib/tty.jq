# Terminal vocabulary: glyphs (Nerd Font, or the mockup's unicode stand-ins) and ANSI
# styles. Callers pass $glyphs ("nerd" | "unicode") and $color (true | false).

# [nerd font (Material Design) codepoint, unicode stand-in]; codepoints match store/lib/format.mjs
# (jq has no \u{...} escape for supplementary-plane characters, hence numbers + implode).
def glyph_table: {
  safe: [986312, "✓"], caution: [986829, "▲"], risky: [983608, "◆"],
  blocked: [984890, "⊘"], unreviewed: [984613, "?"], stale: [983376, "◷"],
  retired: [983100, "▭"], unlisted: [983863, "◌"], unknown: [984613, "?"],
  builtin: [984211, "◇"],
  ok: [983340, "✓"], bad: [983382, "✗"], skip: [983924, "·"], warn: [983082, "!"],
  sig: [988992, "✓sig"], unsig: [984941, "○"], ext: [984012, "↗"],
  commit: [984856, "c"], tree: [984645, "t"], snap: [987662, "▣"], shield: [984217, "◈"]
};
def g($name; $glyphs): glyph_table[$name] // glyph_table.unknown | if $glyphs == "unicode" then .[1] else [.[0]] | implode end;

# State -> SGR. Orange has no ANSI slot: 256-colour 208, the one fixed colour we use.
def sgr: {
  safe: "32", caution: "33", risky: "38;5;208", blocked: "1;31", stale: "34",
  unreviewed: "2", unlisted: "2", retired: "2", unknown: "2", builtin: "2",
  ok: "32", bad: "31", dim: "2", bold: "1", link: "34", sha: "34", head: "1"
};
def paint($style; $color): if $color and (sgr[$style] != null) then "\u001b[\(sgr[$style])m\(.)\u001b[0m" else . end;
