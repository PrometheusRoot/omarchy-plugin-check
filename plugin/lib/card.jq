# Render a model (lib/model.jq) as the terminal verdict card, the unlisted warning or the
# --add refusal (mockup "cli"). Pure text out; colour and glyph set are args.
#   jq -r -L lib --arg mode card|refusal --argjson color B --arg glyphs nerd|unicode -f lib/card.jq
include "opc";
include "tty";

def c($s): paint($s; $color);
def G($n): g($n; $glyphs);
def pad($n): . + (" " * ([$n - length, 0] | max));
def st: . as $s | (G($s) + " " + $s) | c($s);
def eqmark($b): if $b == null then "?" | c("dim") elif $b then "=" | c("ok") else "≠" | c("stale") end;
def row($label; $text): "│  " + ($label | pad(7) | c("dim")) + $text;

def provider_line:
  "\(.id) " + (.verdict | st) + " " + .tier
  + (if .verification == "sigstore" then " " + (G("sig") | c("ok"))
     elif .verification == "unsigned-dev" then " " + ((G("unsig") + "dev") | c("dim"))
     else " " + ((G("unsig") + .verification) | c("dim")) end)
  + (if .capped then " ≤caution" | c("dim") else "" end);

def criteria_line:
  (.checked // []) as $chk | (.failed // []) as $fail
  | ([$chk[] | . as $k | if ($fail | index($k)) then (G("bad") + $k) | c("bad") else (G("ok") + $k) | c("ok") end]
     + [(.notChecked // [])[] | (G("skip") + .) | c("dim")]) | join(" ");

def findings_line:
  (.counts // {}) as $n
  | ([("critical", "high", "medium", "low", "info") as $s | select($n[$s]) | "\($n[$s]) \($s)"] | join(" · "))
  as $sev
  | (if $sev == "" then "none above info" else $sev end) + " · \(.blocking | length) blocking";

def snap_line:
  ((G("ok") + " verified") | c("ok")) + " · \(.age | age) old"
  + (if .catalog then " · catalog \(.catalog[5:10])" else "" end)
  + (if .dev then " · " + ("dev key" | c("warn_dim")) else "" end);

def commit_line:
  if .reviewed.commit == null then "none reviewed" | c("dim")
  else (.reviewed.commit | sha7 | c("sha"))
    + (if (.reviewed.commits | length) > 1 then " +\((.reviewed.commits | length) - 1) more" else "" end)
    + "  " + (if .upstream.head == null then "upstream ?" + (if .upstream.error then " (\(.upstream.error))" else "" end) | c("dim")
              elif .upstream.eq then "= upstream" | c("ok")
              else ("≠ upstream " | c("stale")) + (.upstream.head | sha7 | c("sha")) + " (moved, unreviewed)" | c("stale") end)
  end;

def local_line:
  (.local.head | sha7 | c("sha")) + "  commit " + eqmark(.local.commitEq) + "  tree " + eqmark(.local.treeEq)
  + (if .local.commitEq == false and .local.treeEq == true then "  (same content)" | c("dim") else "" end);

def headline:
  (.state | st) + "  "
  + (if .state == "stale" then "reviewed " + (.combined | st) + " at " + (.reviewed.commit | sha7)
     elif .basis == "trusted" then "combined · worst of \(.counted) trusted"
     elif .basis == "untrusted" then "no trusted review · untrusted rows only"
     else "no provider has reviewed it" end)
  + (if .contested then "  " + ("⚑ contested" | c("risky")) else "" end);

def card:
  [ "╭─ " + (.name | c("head")) + " · " + (.id | c("dim")),
    "│  " + headline,
    (if .timeReviewed then "│  " + ("reviewed \(.timeReviewed[0:10])" | c("dim")) else empty end),
    "│",
    (.providers as $p | if ($p | length) == 0 then row("prov"; "—" | c("dim"))
     else (row("prov"; $p[0] | provider_line), ($p[1:][] | "│         " + provider_line)) end),
    (if .criteria then row("crit"; .criteria | criteria_line) else empty end),
    row("commit"; commit_line),
    (if .local then row("local"; local_line) else empty end),
    (if .viewAvailable then row("find"; .findings | findings_line) else empty end),
    (.findings.blocking[] | "│         " + (.category | pad(12) | c("blocked")) + " " + .message + "  " + ((.at // "") | c("link"))),
    (if .summary then row("note"; .summary) else empty end),
    (if (.mkt | length) > 0 then row("mkt"; .mkt | join(" · ")) else empty end),
    row("snap"; .snapshot | snap_line),
    "╰─ " + ((G("ext") + " " + .url) | c("link"))
  ] | join("\n");

def unlisted:
  [ "  " + ("unlisted" | st) + "  not on plugins.omarchy.org · no provider has reviewed it",
    "  " + (G("warn") | c("caution")) + " no verdict. --add will ask for confirmation; nothing is pinned." ]
  | join("\n");

def refusal:
  [ "  " + (.state | st) + "  " + (.name | c("head")) + "  " + (.id | c("dim")),
    "  " + ([.providers[] | provider_line] | join("   ")),
    "  " + (.snapshot | snap_line),
    (if (.findings.blocking | length) > 0 then
      "", "  hard-fails \(.findings.blocking | length)",
      (.findings.blocking[] | "    " + (.category | pad(12) | c("blocked")) + " " + (.message | pad(36)) + " " + ((.at // "") | c("link")))
     else empty end),
    "",
    "  " + ((G("bad") + " refusing to run omarchy plugin add.") | c("bad"))
      + (if .state == "blocked" then " --force is not honored for blocked plugins." else " \(.gate.reason)." end),
    "  report " + (.url | c("link"))
  ] | join("\n");

if $mode == "refusal" then refusal elif .id == null then unlisted else card end
