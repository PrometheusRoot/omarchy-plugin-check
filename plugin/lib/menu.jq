# Idempotent edit of ~/.config/omarchy/extensions/omarchy-menu.jsonc: add or remove our
# entries as one marked block, keep every other byte. Fails (error) rather than writing a
# file the shell's JSONC reader (MenuModel.stripJsonc + JSON.parse) would reject.
#   jq -R -s -j -L lib --arg mode add|remove --argjson entries '{"id": {...}}' -f lib/menu.jq FILE
include "opc";

def begin_marker: "// BEGIN omarchy-plugin-check (managed by `omarchy-plugin-check setup`; `setup --uninstall` removes it)";
def end_marker: "// END omarchy-plugin-check";

def parses: try (strip_jsonc | fromjson | type == "object") catch false;

# Drop our block (markers included) wherever it is.
def without_block:
  split("\n")
  | reduce .[] as $l ({out: [], skip: false};
      if ($l | sub("^\\s+"; "") | startswith("// BEGIN omarchy-plugin-check")) then .skip = true
      elif .skip and ($l | sub("^\\s+"; "") | startswith(end_marker)) then .skip = false
      elif .skip then .
      else .out += [$l] end)
  | .out | join("\n");

def block:
  ["  " + begin_marker]
  + [$entries | to_entries[] | "  \(.key | tojson): \(.value | tojson),"]
  + ["  " + end_marker];

def is_filler: test("^\\s*$") or test("^\\s*//");

# Insert the block before the closing brace; give the previous entry a comma if it lacks one.
def with_block:
  . as $text
  # why: jq < 1.8 returns byte offsets from string rindex; a codepoint offset is needed for slicing
  # (the menu holds Nerd Font glyphs), so search the exploded codepoints instead.
  | ($text | explode | rindex(125)) as $close
  | if $close == null then error("no closing } in the menu file") else . end
  | ($text[:$close] | split("\n")) as $head
  | ([range($head | length - 1; -1; -1) | select($head[.] | is_filler | not)] | first) as $last
  | (if $last == null then $head
     else ($head[$last] | sub("\\s+$"; "")) as $l
       | if ($l | endswith("{") or endswith(",")) then $head
         else $head[:$last] + [$l + ","] + $head[$last + 1:] end
     end) as $head2
  | ($head2[:-1] + block + [$head2[-1]]) | join("\n") | . + $text[$close:];

(if test("^\\s*$") then "{\n}\n" else . end)
| (if parses then . else error("the existing menu file does not parse as the shell reads it; not touching it") end)
| without_block
| (if $mode == "add" then with_block else . end)
| if parses then . else error("refusing to write a menu file the shell could not parse") end
