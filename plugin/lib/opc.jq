# Shared, pure definitions for omarchy-plugin-check (no I/O). Included by the other
# filters with `include "opc";` and `jq -L plugin/lib`. Tested through tests/*.bats.

# Lower-cased "host/owner/repo" key for a git URL, or null when the URL names no
# remote repository we can match (file://, bare paths, helpers).
def repo_key:
  if type != "string" then null
  # why: fast path for the snapshot's own canonical form; the regex below costs ~1 ms a call.
  elif startswith("https://github.com/")
    and (ltrimstr("https://github.com/") | split("/") | length == 2 and all(.[]; . != "" and . != "." and . != ".." and (contains(":") or contains("@") or contains("?") or contains("#") | not))) then
    "github.com/" + (ltrimstr("https://github.com/") | rtrimstr(".git") | ascii_downcase)
  else
    (gsub("^\\s+|\\s+$"; "")) as $u
    | ($u | capture("^(?:git\\+)?(?:https?|ssh|git)://(?:[^@/]+@)?(?<host>[^/:]+)(?::[0-9]+)?/(?<path>[^?#]+?)(?:\\.git)?/*$")
       // ($u | capture("^[^@/:]+@(?<host>[^/:]+):(?<path>[^?#]+?)(?:\\.git)?/*$"))
       // null) as $m
    | if $m == null or ($m.path | test("(^|/)\\.\\.?(/|$)")) or ($m.path | test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$") | not) then null
      else ($m.host + "/" + $m.path) | ascii_downcase
      end
  end;

def is_plugin_id: type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]*$") and (contains("..") | not);
def is_sha: type == "string" and test("^[0-9a-f]{40}$");
def sha7: if type == "string" then .[0:7] else "—" end;

# Installed-plugin states, worst last. "builtin" never appears for an installed dir.
def states: ["safe", "caution", "unreviewed", "unlisted", "stale", "retired", "risky", "blocked"];
def state_rank: . as $s | states | index($s) // 2;
def worst_state: if length == 0 then null else max_by(state_rank) end;

def marketplace_url: "https://plugins.omarchy.org/plugin.html?id=" + (@uri);

# What was reviewed for one snapshot row: the signed commit (snapshot) or, failing that,
# the commits of the unsigned per-plugin view; the tree only from the view, and only for
# a counted core/verified row of a reviewed commit. $detail must already belong to $row.
def reviewed($row; $detail):
  ([$row.verdict.commit | select(is_sha)]) as $signed
  | (if ($signed | length) > 0 then $signed
     elif $row.verdict.basis == "trusted" then [($detail.combined.commits // [])[] | select(is_sha)]
     else [] end) as $commits
  | {
      commits: $commits,
      signed: (($signed | length) > 0),
      tree: ([($detail.providers // [])[]
              | select(.counted == true and (.tier == "core" or .tier == "verified"))
              | select(.commit as $c | $commits | index($c))
              | .tree | select(is_sha)] | first)
    };

# State of an installed (or about-to-be-installed) plugin.
#   $row: snapshot row or null · $local: {head, tree} (nulls allowed) · $rev: reviewed(...)
def classify($row; $local; $rev):
  if $row == null or $row.state == "builtin" then "unlisted"
  elif $row.state == "retired" then "retired"
  elif $row.verdict.combined == "blocked" then "blocked"
  elif $row.verdict.basis != "trusted" or ($row.verdict.combined | IN("safe", "caution", "risky") | not) then "unreviewed"
  elif ($local.head != null and ($rev.commits | index($local.head)))
    or ($local.tree != null and $rev.tree != null and $local.tree == $rev.tree) then $row.verdict.combined
  else "stale"
  end;

# --add gate: {action: refuse|confirm|proceed, code, reason}.
def gate($state; $row):
  if $state == "blocked" then {action: "refuse", code: 2, reason: "blocked"}
  elif $state == "retired" then {action: "refuse", code: 2, reason: "retired from plugins.omarchy.org"}
  elif $row != null and $row.state == "builtin" then {action: "refuse", code: 1, reason: "built into Omarchy; nothing to add"}
  elif $row != null and $row.install == "" then {action: "refuse", code: 1, reason: "the marketplace lists no `omarchy plugin add` install for it"}
  elif $state == "safe" then {action: "proceed", code: 0, reason: "safe"}
  else {action: "confirm", code: 0, reason: $state}
  end;

# Seconds -> "45s" | "12m" | "5h" | "3d".
def age:
  if . == null then "?"
  elif . < 60 then "\(floor)s"
  elif . < 3600 then "\(. / 60 | floor)m"
  elif . < 172800 then "\(. / 3600 | floor)h"
  else "\(. / 86400 | floor)d"
  end;

def iso_to_epoch: if type == "string" then (sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) else null end;

# Same as omarchy-shell's MenuModel.stripJsonc: whole-line // comments, trailing commas.
def strip_jsonc: gsub("(?m)^\\s*//[^\\n]*(\\n|$)"; "") | gsub(",(?<s>\\s*[}\\]])"; "\(.s)");

# Index lookup for a plugin id or a git URL: {by, key, rows}. Several rows = a suite or
# monorepo listing more than one plugin from one repository.
def resolve($q):
  if ($q | is_plugin_id) and .ids[$q] != null then {by: "id", key: $q, rows: [.ids[$q]]}
  else ($q | repo_key) as $k
    | {by: "repo", key: $k, rows: (if $k == null then [] else [(.repos[$k] // [])[] as $i | .ids[$i]] end)}
  end;
