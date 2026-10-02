# Status document (lib/status.jq) -> the `status` table (mockup "cli · status").
#   jq -r -L lib --argjson color B --arg glyphs nerd|unicode -f lib/table.jq status.json
include "opc";
include "tty";

def c($s): paint($s; $color);
def G($n): g($n; $glyphs);
def pad($n): . + (" " * ([$n - length, 0] | max));
def cut($n): if length > $n then "…" + .[length - $n + 1:] else . end;
def eqm: if . == null then "—" | c("dim") elif . then "=" | c("ok") else "≠" | c("stale") end;
def prov($p): [$p | to_entries[] | .key + (if .value == "safe" then G("ok") | c("ok") elif .value == "unknown" then "?" else ":" + .value end)] | join(" ");

(.generatedAt | iso_to_epoch) as $now
| (.plugins | map(.id | length) | max // 6 | [., 28] | min) as $w
| [
    (" " + ("state" | pad(14)) + ("plugin" | pad($w + 2)) + ("installed" | pad(11)) + ("reviewed" | pad(10)) + "c t  prov" | c("dim")),
    (.plugins[] | .state as $s |
      " " + ((G($s) + " " + $s) | pad(14) | c($s))
      + (.id | cut($w) | pad($w + 2))
      + (.head | sha7 | pad(11) | c("sha"))
      + (.reviewed.commit | sha7 | pad(10) | c("sha"))
      + (.commitMatch | eqm) + " " + (.treeMatch | eqm) + "  "
      + (if .note then .note | c("dim")
         elif $s == "unlisted" then "not on plugins.omarchy.org" | c("dim")
         elif $s == "retired" then "removed from the marketplace" | c("dim")
         elif (.providers | length) == 0 then "no provider has reviewed it" | c("dim")
         else prov(.providers) end)
      + (if .contested then " " + ("⚑contested" | c("risky")) else "" end)),
    "",
    (.plugins[] | select(.repin != null) | " " + (G("commit") | c("stale")) + " "
      + (if .repin == "forward" then "\(.id): reviewed update to \(.reviewed.commit | sha7)"
         else "\(.id): HEAD \(.head | sha7) is past the review; back to \(.reviewed.commit | sha7)" end)
      + " · " + ("omarchy-plugin-check pin \(.listedId)" | c("bold"))),
    " " + ([(.plugins | length | "\(.) plugins")] + [(.counts | to_entries | sort_by(-(.key | state_rank))[] | select(.key != "safe") | "\(.value) \(.key)")] | join(" · ")),
    " " + ("c = commit match · t = tree match (installed vs reviewed) · state worst first" | c("dim")),
    " " + (.snapshot | if .ok then (G("ok") + " snapshot verified" | c("ok")) + " · \(($now - (.generatedAt | iso_to_epoch)) | age) old · version \(.version)" + (if .dev then " · dev key" else "" end)
           else (G("bad") + " no verified snapshot" | c("bad")) + " · \(.error // "run omarchy-plugin-check update")" end)
  ] | join("\n")
