# `pin <id>`: re-pin an installed plugin to the snapshot's reviewed commit (ADR-0035). Pure.
#   jq -L lib --argjson facts F --argjson prev P -f lib/pin.jq <status entry (lib/status.jq)>
# $facts: null before fetching, else {head, upstream, rel: behind|ahead|diverged|missing,
#   forward, back (commit counts), stat (git --shortstat), files: ["M\tpath", ...], tree}
#   where tree = the reviewed commit's tree in the checkout
# $prev: the last pin record of this plugin ({commit, verdict, at}) or null
# -> {action: refuse|fetch|current|confirm, code, lines: [...], prompt}
include "opc";

def refuse($code; $why): {action: "refuse", code: $code, lines: [$why], prompt: null};

.reviewed.commit as $c
| (.combined // "unknown") as $verdict
| if .listedId == null then refuse(3; "\(.id) is unlisted (\(.note // "not on plugins.omarchy.org")); nothing reviewed to pin")
  elif .state == "retired" then refuse(2; "\(.listedId) was retired from plugins.omarchy.org; nothing to pin")
  elif .state == "blocked" then refuse(2; "\(.listedId) is blocked; refusing to pin it (remove it: omarchy plugin remove \(.id))")
  elif .reviewed.signed != true or ($c | is_sha | not) then
    refuse(1; "\(.listedId) has no single reviewed commit in the snapshot (\(.state)); nothing to pin")
  elif $facts == null then {action: "fetch", code: 0, lines: [], prompt: null}
  elif $facts.tree != null and .reviewed.tree != null and $facts.tree != .reviewed.tree then
    refuse(1; "the reviewed commit \($c | sha7) in the upstream repository does not have the attested tree \(.reviewed.tree | sha7)")
  else
    ($facts.upstream != null and $facts.upstream != $c) as $upAhead
    | if $facts.head == $c or (.treeMatch == true) then
        {action: "current", code: 0, prompt: null, lines: (
          ["\(.listedId) is at the reviewed commit \($c | sha7) (\($verdict))"]
          + (if $upAhead and $facts.upstream != $facts.head then
               ["upstream HEAD \($facts.upstream | sha7) is newer but unreviewed (stale); nothing to pin until a provider reviews it"]
             else [] end))}
      else
        (if $prev != null and $prev.commit == $facts.head then "\($prev.verdict) (pinned \($prev.at[0:10]))"
         else "\(.state): no review of \($facts.head | sha7)" end) as $from
        | {action: "confirm", code: 0,
           prompt: "Check out the reviewed commit \($c | sha7) (\($verdict)) in \(.id)?",
           lines: (
             ["\(.listedId)  \($facts.head | sha7) → \($c | sha7)  "
               + (if $facts.rel == "behind" then "forward \($facts.forward) commit(s)"
                  elif $facts.rel == "ahead" then "back: HEAD is \($facts.back) commit(s) past the review (unreviewed)"
                  else "diverged: \($facts.forward) reviewed / \($facts.back) unreviewed commit(s) apart" end),
              "verdict  \($from) → \($verdict)" + (if .contested then " (contested)" else "" end),
              "files    " + (if ($facts.stat // "") == "" then "no content change" else $facts.stat end)]
             + [$facts.files[:15][] | "         " + sub("\t"; "  ")]
             + (if ($facts.files | length) > 15 then ["         … \(($facts.files | length) - 15) more"] else [] end)
             + (if .moved then ["origin   \(.origin) is a former name; fetched from \(.repo)"] else [] end)
             + (if $upAhead then ["upstream HEAD \($facts.upstream | sha7) is past the review (unreviewed); pinning the reviewed commit"] else [] end))}
      end
  end
