# Idempotent edit of the Hyprland bindings file (~/.config/hypr/bindings.lua, or the older
# bindings.conf): our keybind as one marked block, every other byte kept. Pure.
#   jq -R -s -j -L lib --arg mode add|remove|current --arg format lua|conf --arg key K --arg cmd PATH -f lib/hypr.jq FILE
# current: prints the key our block binds ("" when there is none).

def comment: if $format == "lua" then "--" else "#" end;
def begin_marker: comment + " BEGIN omarchy-store (managed by `omarchy-plugin-check setup`; `setup --uninstall` removes it)";
def end_marker: comment + " END omarchy-store";
def strip: sub("^\\s+"; "") | sub("\\s+$"; "");

def lines: split("\n");
def is_begin: strip | startswith(comment + " BEGIN omarchy-store");
def is_end: strip | startswith(end_marker);

# Lines between our markers (markers excluded).
def block_lines:
  lines | reduce .[] as $l ({in: false, out: []};
    if ($l | is_begin) then .in = true
    elif .in and ($l | is_end) then .in = false
    elif .in then .out += [$l]
    else . end) | .out;

def without_block:
  lines | reduce .[] as $l ({skip: false, out: []};
    if ($l | is_begin) then .skip = true
    elif .skip and ($l | is_end) then .skip = false
    elif .skip then .
    else .out += [$l] end) | .out | join("\n");

# "SUPER + SHIFT + S" -> conf "SUPER SHIFT, S"
def conf_combo: split("+") | map(strip) | (.[:-1] | join(" ")) + ", " + .[-1];

def bind_line:
  if $format == "lua" then "o.bind(\($key | tojson), \"omarchy-store\", \($cmd | tojson))"
  else "bindd = \($key | conf_combo), omarchy-store, exec, \($cmd)" end;

def current_key:
  [block_lines[] | strip | select(. != "")] | first // ""
  | if . == "" then ""
    elif $format == "lua" then (capture("^o\\.bind\\(\"(?<k>[^\"]+)\"") // {k: ""}).k
    else (capture("^bindd\\s*=\\s*(?<m>[^,]*),\\s*(?<k>[^,]+),") // null)
      | if . == null then "" else ((.m | strip | split(" ") | map(select(. != ""))) + [.k | strip]) | join(" + ") end
    end;

if $mode == "current" then current_key
else
  without_block
  | if $mode == "add" then
      (if . == "" or endswith("\n") then . else . + "\n" end) + begin_marker + "\n" + bind_line + "\n" + end_marker + "\n"
    else . end
end
